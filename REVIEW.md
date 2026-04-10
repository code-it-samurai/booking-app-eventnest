# Code Review — EventNest API

**Reviewer:** code-reviewer
**Date:** 2026-04-10

---

## Executive Summary

The EventNest Rails API contains **critical security vulnerabilities** that would allow attackers to extract arbitrary data from the database, access other users' orders and payment details, and modify or delete any event without authorization. These issues must be fixed before any production deployment.

---

## Issue #1 — SQL Injection in Event Search

| Field | Value |
|-------|-------|
| **File** | `app/controllers/api/v1/events_controller.rb:10` |
| **Category** | Security |
| **Severity** | CRITICAL |

**Description:**
The search parameter is interpolated directly into a raw SQL string using `"title LIKE '%#{params[:search]}%'"`. This is a textbook SQL injection vulnerability. An attacker can inject arbitrary SQL to bypass filters, extract sensitive data from any table (users, payments, orders), or even modify/delete data. No authentication is required since the `index` action skips auth.

**Recommended Fix:**
Use parameterized queries: `where("title LIKE ? OR description LIKE ?", "%#{params[:search]}%", "%#{params[:search]}%")` or use ActiveRecord's `sanitize_sql_like` for safe LIKE pattern escaping.

### Proof

**Normal search (no results):**
```bash
curl -s "http://localhost:3000/api/v1/events?search=nonexistent"
```
Response: `[]`

**SQL Injection (bypasses published/upcoming filters, returns ALL events including draft and past):**
```bash
curl -s "http://localhost:3000/api/v1/events?search=%27)%20OR%201%3D1%20--"
```
Response: Returns **5 events** including the draft "Untitled Yoga Retreat" (id=4, status=draft) and the past "Diwali Night Market 2024" (id=5, starts_at=2026-02-10) — both of which should be hidden by the `published` and `upcoming` scopes. This proves arbitrary SQL execution via the search parameter.

---

## Issue #2 — Broken Authorization: All Orders Exposed to Any Authenticated User

| Field | Value |
|-------|-------|
| **File** | `app/controllers/api/v1/orders_controller.rb:6` |
| **Category** | Security |
| **Severity** | CRITICAL |

**Description:**
The `index` action queries `Order.all` instead of scoping to `current_user.orders`. Any authenticated user can see every order in the system, including other users' confirmation numbers, total amounts, and event details. The `show` and `cancel` actions also lack ownership checks — any user can view or cancel any other user's order.

**Recommended Fix:**
Scope all queries to `current_user.orders`. Add ownership checks in `show` and `cancel` actions, returning 403 Forbidden for unauthorized access.

### Proof

**Vikram (user_id=4) accesses Ananya's order (order_id=1, user_id=3):**
```bash
# Login as Vikram
VIKRAM_TOKEN=$(curl -s -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"vikram@example.com","password":"password123"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

# Vikram views Ananya's order details including payment info
curl -s http://localhost:3000/api/v1/orders/1 \
  -H "Authorization: Bearer $VIKRAM_TOKEN"
```
Response:
```json
{
  "id": 1,
  "confirmation_number": "EVN-A1B2C3D4",
  "status": "confirmed",
  "total_amount": 2998.0,
  "event": { "id": 1, "title": "Mumbai Indie Music Festival 2025" },
  "items": [{ "ticket_tier": "Regular", "quantity": 2, "unit_price": 1499.0 }],
  "payment": { "status": "completed", "provider_reference": "ch_abc123def456" }
}
```
Vikram can see Ananya's full order including payment provider reference — a clear data privacy violation.

---

## Issue #3 — Broken Authorization: Any User Can Update/Delete Any Event

| Field | Value |
|-------|-------|
| **File** | `app/controllers/api/v1/events_controller.rb:89-103` |
| **Category** | Security |
| **Severity** | HIGH |

**Description:**
The `update` and `destroy` actions find events by `Event.find(params[:id])` without checking if `current_user` is the event owner. Any authenticated user — including attendees — can modify or delete any event in the system. There is no role check (organizer vs. attendee) either.

**Recommended Fix:**
Scope mutations to `current_user.events.find(params[:id])` or add an explicit authorization check. Also restrict `create`, `update`, and `destroy` to organizer role only.

---

## Issue #4 — SQL Injection via ORDER BY Clause

| Field | Value |
|-------|-------|
| **File** | `app/controllers/api/v1/events_controller.rb:21` |
| **Category** | Security |
| **Severity** | HIGH |

**Description:**
The `sort_by` parameter is passed directly to `.order()`: `events.order(params[:sort_by] || "starts_at ASC")`. While Rails has some protection against arbitrary SQL in `.order()`, this can still be exploited for SQL injection in certain database adapters and Rails versions. An attacker could inject `(CASE WHEN (SELECT...) THEN 1 ELSE 2 END)` to perform blind SQL injection. This endpoint requires no authentication.

**Recommended Fix:**
Whitelist allowed sort columns: `allowed = %w[starts_at title created_at]; sort = allowed.include?(params[:sort_by]) ? params[:sort_by] : "starts_at ASC"`.

---

## Issue #5 — Race Condition in Ticket Reservation (Overselling)

| Field | Value |
|-------|-------|
| **File** | `app/models/ticket_tier.rb:17-24` |
| **Category** | Data Integrity |
| **Severity** | HIGH |

**Description:**
`reserve_tickets!` performs a read-then-write on `sold_count` without database-level locking. Under concurrent requests, two users can both read the same `available_quantity`, both pass the check, and both increment `sold_count` — selling more tickets than available. This is a classic TOCTOU (time-of-check-to-time-of-use) race condition.

**Recommended Fix:**
Use `with_lock` for pessimistic locking, or use an atomic SQL update: `TicketTier.where(id: id).where("quantity - sold_count >= ?", count).update_all("sold_count = sold_count + #{count.to_i}")` and check the return value.

---

## Issue #6 — N+1 Queries in Events Index

| Field | Value |
|-------|-------|
| **File** | `app/controllers/api/v1/events_controller.rb:23-45` |
| **Category** | Performance |
| **Severity** | MEDIUM |

**Description:**
The `index` action iterates over events and accesses `event.user.name` and `event.ticket_tiers` for each event without eager loading. With N events, this produces 1 + N (users) + N (ticket_tiers) = 2N+1 queries. As the event count grows, this will cause significant latency and database load on every page view of the events listing.

**Recommended Fix:**
Add eager loading: `events = events.includes(:user, :ticket_tiers)` before the iteration.

---

## Issue #7 — Mass Assignment of `sold_count` in TicketTiersController

| Field | Value |
|-------|-------|
| **File** | `app/controllers/api/v1/ticket_tiers_controller.rb:53` |
| **Category** | Data Integrity |
| **Severity** | MEDIUM |

**Description:**
The `tier_params` method permits `sold_count` in the strong parameters: `params.require(:ticket_tier).permit(:name, :price, :quantity, :sold_count, ...)`. This means any authenticated user can manually set the number of tickets "sold" via the API, bypassing all inventory logic. An organizer (or any user, since there's no role check) could set `sold_count` to 0 to "restock" sold-out tiers, or inflate it to fake scarcity.

**Recommended Fix:**
Remove `:sold_count` from `tier_params`. This field should only be modified by the `reserve_tickets!` method during order creation.

---

## Additional Observations (Not in Top 7)

- **User enumeration via login:** Login returns different error messages for "no account" vs "invalid password" (`auth_controller.rb:24-28`), allowing attackers to enumerate valid email addresses.
- **Synchronous email delivery:** `deliver_now` in callbacks (`event.rb:39,49`, `order.rb:54,65,67`) blocks the request thread. Should use `deliver_later`.
- **Hardcoded secret keys:** `config/secrets.yml` contains hardcoded development/test secret keys in version control.
- **No pagination:** `events#index` and `orders#index` have no pagination — will cause memory/performance issues at scale.
- **`geocode_venue` has `sleep(0.1)`:** Artificial delay in a `before_save` callback (`event.rb:31`) slows every event save.
