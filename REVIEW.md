# Code Review — EventNest API

**Reviewer:** code-reviewer
**Date:** 2026-04-10

---

## Executive Summary

The EventNest Rails API contains **critical security vulnerabilities** that would allow attackers to extract arbitrary data from the database, access other users' orders and payment details, and modify or delete any event without authorization. These issues must be fixed before any production deployment.

---

## Prerequisites for Reproducing Proofs

All curl proofs below assume:

1. The app is running locally on `http://localhost:3000`
2. The database has been seeded with `rails db:seed`

**Seed data reference (from `db/seeds.rb`):**

| User | Email | Role | user_id |
|------|-------|------|---------|
| Priya Mehta | priya@eventnest.dev | organizer | 1 |
| Rahul Sharma | rahul@eventnest.dev | organizer | 2 |
| Ananya Gupta | ananya@example.com | attendee | 3 |
| Vikram Patel | vikram@example.com | attendee | 4 |
| Sneha Reddy | sneha@example.com | attendee | 5 |

| Order | user_id | event | status |
|-------|---------|-------|--------|
| 1 | 3 (Ananya) | Mumbai Indie Music Festival | confirmed |
| 2 | 4 (Vikram) | RailsConf India | confirmed |
| 3 | 5 (Sneha) | PostgreSQL Workshop | pending |
| 4 | 3 (Ananya) | RailsConf India | cancelled |

**All passwords are `password123`.**

**Helper — get an auth token:**
```bash
# Replace EMAIL with the user's email
TOKEN=$(curl -s -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"EMAIL","password":"password123"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
```

---

## Issue #1 — SQL Injection in Event Search (FIXED)

| Field | Value |
|-------|-------|
| **File** | `app/controllers/api/v1/events_controller.rb:10` |
| **Category** | Security |
| **Severity** | CRITICAL |
| **Status** | **FIXED** in this branch |

**Description:**
The search parameter was interpolated directly into a raw SQL string using `"title LIKE '%#{params[:search]}%'"`. This is a textbook SQL injection vulnerability. An attacker could inject arbitrary SQL to bypass filters, extract sensitive data from any table (users, payments, orders), or even modify/delete data. No authentication is required since the `index` action skips auth.

**Vulnerable code:**
```ruby
# app/controllers/api/v1/events_controller.rb:10 (BEFORE fix)
events = events.where("title LIKE '%#{params[:search]}%' OR description LIKE '%#{params[:search]}%'")
```

**Recommended Fix (applied):**
Use parameterized queries with `sanitize_sql_like`:
```ruby
search_term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:search])}%"
events = events.where("title LIKE ? OR description LIKE ?", search_term, search_term)
```

### Proof

> **Note:** Issue #1 has been fixed. The "BEFORE" output below was captured prior to the fix.

**Step 1 — Baseline: confirm only 3 published upcoming events are visible (no auth required):**
```bash
curl -s "http://localhost:3000/api/v1/events"
```
Response (3 events — PostgreSQL Workshop, Music Festival, RailsConf):
```json
[
  { "id": 3, "title": "Advanced PostgreSQL Workshop", ... },
  { "id": 1, "title": "Mumbai Indie Music Festival 2025", ... },
  { "id": 2, "title": "RailsConf India 2025", ... }
]
```

**Step 2 — BEFORE fix: SQL injection bypasses published/upcoming filters:**
```bash
# The payload ') OR 1=1 -- closes the LIKE clause and injects OR 1=1
# URL-encoded: %27 = '  %20 = space  %3D = =
curl -s "http://localhost:3000/api/v1/events?search=%27)%20OR%201%3D1%20--"
```
Response (BEFORE fix) — **5 events** returned, including draft and past events that should be hidden:
```json
[
  { "id": 1, "title": "Mumbai Indie Music Festival 2025" },
  { "id": 2, "title": "RailsConf India 2025" },
  { "id": 3, "title": "Advanced PostgreSQL Workshop" },
  { "id": 4, "title": "Untitled Yoga Retreat", "status": "draft" },
  { "id": 5, "title": "Diwali Night Market 2024", "starts_at": "2026-02-10..." }
]
```
Event #4 is a **draft** (should never appear publicly). Event #5 is **past** (should be filtered by `upcoming` scope). The injected `OR 1=1` bypassed both the `published` and `upcoming` WHERE clauses.

**Step 3 — AFTER fix: same payload treated as literal text, returns nothing:**
```bash
curl -s "http://localhost:3000/api/v1/events?search=%27)%20OR%201%3D1%20--"
```
Response:
```json
[]
```
No events match the literal string `') OR 1=1 --` in their title or description. The injection is neutralized.

**Step 4 — Legitimate search still works after fix:**
```bash
curl -s "http://localhost:3000/api/v1/events?search=PostgreSQL"
```
Response:
```json
[
  { "id": 3, "title": "Advanced PostgreSQL Workshop", ... }
]
```

---

## Issue #2 — Broken Authorization: All Orders Exposed to Any Authenticated User

| Field | Value |
|-------|-------|
| **File** | `app/controllers/api/v1/orders_controller.rb:6` |
| **Category** | Security |
| **Severity** | CRITICAL |

**Description:**
The `index` action queries `Order.all` instead of scoping to `current_user.orders`. Any authenticated user can see every order in the system, including other users' confirmation numbers, total amounts, and event details. The `show` and `cancel` actions also lack ownership checks — any user can view or cancel any other user's order.

**Vulnerable code:**
```ruby
# app/controllers/api/v1/orders_controller.rb:6
def index
  orders = Order.all.order(created_at: :desc)  # No scoping to current_user!
  ...
end
```

**Recommended Fix:**
Scope all queries to `current_user.orders`. Add ownership checks in `show` and `cancel` actions, returning 403 Forbidden for unauthorized access.

### Proof

**Step 1 — Login as Vikram (attendee, user_id=4). Vikram only has order #2:**
```bash
# Login as Vikram
curl -s -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"vikram@example.com","password":"password123"}'
```
Response:
```json
{
  "token": "eyJhbGciOiJIUzI1NiJ9...",
  "user": { "id": 4, "name": "Vikram Patel", "email": "vikram@example.com", "role": "attendee" }
}
```

**Step 2 — Vikram lists ALL orders (sees all 4, not just his own #2):**
```bash
VIKRAM_TOKEN="<token from step 1>"

curl -s http://localhost:3000/api/v1/orders \
  -H "Authorization: Bearer $VIKRAM_TOKEN"
```
Response — Vikram sees **all 4 orders** from all users:
```json
[
  { "id": 4, "confirmation_number": "EVN-M3N4O5P6", "event": "RailsConf India 2025", "status": "cancelled", "total_amount": 2499.0 },
  { "id": 3, "confirmation_number": "EVN-I9J0K1L2", "event": "Advanced PostgreSQL Workshop", "status": "pending", "total_amount": 1999.0 },
  { "id": 2, "confirmation_number": "EVN-E5F6G7H8", "event": "RailsConf India 2025", "status": "confirmed", "total_amount": 4999.0 },
  { "id": 1, "confirmation_number": "EVN-A1B2C3D4", "event": "Mumbai Indie Music Festival 2025", "status": "confirmed", "total_amount": 2998.0 }
]
```

**Step 3 — Vikram views Ananya's order #1 details, including payment provider reference:**
```bash
curl -s http://localhost:3000/api/v1/orders/1 \
  -H "Authorization: Bearer $VIKRAM_TOKEN"
```
Response — full order detail for another user's order:
```json
{
  "id": 1,
  "confirmation_number": "EVN-A1B2C3D4",
  "status": "confirmed",
  "total_amount": 2998.0,
  "event": { "id": 1, "title": "Mumbai Indie Music Festival 2025", "starts_at": "2026-05-01T01:37:20.488Z" },
  "items": [{ "ticket_tier": "Regular", "quantity": 2, "unit_price": 1499.0, "subtotal": 2998.0 }],
  "payment": { "status": "completed", "provider_reference": "ch_abc123def456" }
}
```
Vikram can see Ananya's full order including the Stripe payment reference — a clear **data privacy violation**.

---

## Issue #3 — Broken Authorization: Any User Can Update/Delete Any Event

| Field | Value |
|-------|-------|
| **File** | `app/controllers/api/v1/events_controller.rb:89-103` |
| **Category** | Security |
| **Severity** | HIGH |

**Description:**
The `update` and `destroy` actions find events by `Event.find(params[:id])` without checking if `current_user` is the event owner. Any authenticated user — including attendees — can modify or delete any event in the system. There is no role check (organizer vs. attendee) either.

**Vulnerable code:**
```ruby
# app/controllers/api/v1/events_controller.rb:89
def update
  event = Event.find(params[:id])     # No ownership check!
  if event.update(event_params)       # Any user can update any event
    ...
end

# app/controllers/api/v1/events_controller.rb:99
def destroy
  event = Event.find(params[:id])     # No ownership check!
  event.destroy                        # Any user can delete any event
  ...
end
```

**Recommended Fix:**
Scope mutations to `current_user.events.find(params[:id])` or add an explicit authorization check. Also restrict `create`, `update`, and `destroy` to organizer role only.

### Proof

**Step 1 — Login as Ananya (attendee, user_id=3) — she does NOT own any events:**
```bash
curl -s -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"ananya@example.com","password":"password123"}'
```
Response:
```json
{
  "token": "eyJhbGciOiJIUzI1NiJ9...",
  "user": { "id": 3, "name": "Ananya Gupta", "email": "ananya@example.com", "role": "attendee" }
}
```

**Step 2 — Confirm event #5 exists and is owned by Priya (organizer):**
```bash
curl -s http://localhost:3000/api/v1/events/5
```
Response:
```json
{
  "id": 5,
  "title": "Diwali Night Market 2024",
  "venue": "Jawaharlal Nehru Stadium, Delhi",
  "status": "published",
  "organizer": { "id": 1, "name": "Priya Mehta" },
  ...
}
```

**Step 3 — Ananya (attendee) deletes Priya's event — succeeds with 204 No Content:**
```bash
ANANYA_TOKEN="<token from step 1>"

curl -s -X DELETE http://localhost:3000/api/v1/events/5 \
  -H "Authorization: Bearer $ANANYA_TOKEN" \
  -w "\nHTTP Status: %{http_code}\n"
```
Response:
```
HTTP Status: 204
```

**Step 4 — Event #5 is permanently deleted:**
```bash
curl -s http://localhost:3000/api/v1/events/5
```
Response:
```json
{ "status": 404, "error": "Not Found" }
```
An attendee deleted an organizer's event without any authorization check.

---

## Issue #4 — SQL Injection via ORDER BY Clause

| Field | Value |
|-------|-------|
| **File** | `app/controllers/api/v1/events_controller.rb:21` |
| **Category** | Security |
| **Severity** | HIGH |

**Description:**
The `sort_by` parameter is passed directly to `.order()`: `events.order(params[:sort_by] || "starts_at ASC")`. While Rails has some protection against arbitrary SQL in `.order()`, this can still be exploited for SQL injection in certain database adapters and Rails versions. An attacker could inject `(CASE WHEN (SELECT...) THEN 1 ELSE 2 END)` to perform blind SQL injection. This endpoint requires no authentication.

**Vulnerable code:**
```ruby
# app/controllers/api/v1/events_controller.rb:21
events = events.order(params[:sort_by] || "starts_at ASC")
```

**Recommended Fix:**
Whitelist allowed sort columns:
```ruby
ALLOWED_SORTS = %w[starts_at title created_at].freeze
sort_col = ALLOWED_SORTS.include?(params[:sort_by]) ? params[:sort_by] : "starts_at ASC"
events = events.order(sort_col)
```

---

## Issue #5 — Race Condition in Ticket Reservation (Overselling)

| Field | Value |
|-------|-------|
| **File** | `app/models/ticket_tier.rb:17-24` |
| **Category** | Data Integrity |
| **Severity** | HIGH |

**Description:**
`reserve_tickets!` performs a read-then-write on `sold_count` without database-level locking. Under concurrent requests, two users can both read the same `available_quantity`, both pass the check, and both increment `sold_count` — selling more tickets than available. This is a classic TOCTOU (time-of-check-to-time-of-use) race condition.

**Vulnerable code:**
```ruby
# app/models/ticket_tier.rb:17-24
def reserve_tickets!(count)
  if available_quantity >= count     # Read: check available
    self.sold_count += count          # Write: increment in memory
    save!                             # Persist — but another thread may have written first
  else
    raise "Not enough tickets available"
  end
end
```

**Recommended Fix:**
Use pessimistic locking or an atomic SQL update:
```ruby
def reserve_tickets!(count)
  with_lock do
    raise "Not enough tickets available" unless available_quantity >= count
    self.sold_count += count
    save!
  end
end
```
Or atomically:
```ruby
rows = TicketTier.where(id: id)
  .where("quantity - sold_count >= ?", count)
  .update_all("sold_count = sold_count + #{count.to_i}")
raise "Not enough tickets available" if rows == 0
```

---

## Issue #6 — N+1 Queries in Events Index

| Field | Value |
|-------|-------|
| **File** | `app/controllers/api/v1/events_controller.rb:23-45` |
| **Category** | Performance |
| **Severity** | MEDIUM |

**Description:**
The `index` action iterates over events and accesses `event.user.name` and `event.ticket_tiers` for each event without eager loading. With N events, this produces 1 + N (users) + N (ticket_tiers) = 2N+1 queries. As the event count grows, this will cause significant latency and database load on every page view of the events listing.

**Vulnerable code:**
```ruby
# app/controllers/api/v1/events_controller.rb:7-8
events = Event.published.upcoming
# ... filters ...
# Line 33: event.user.name       ← triggers N separate User queries
# Line 36: event.ticket_tiers    ← triggers N separate TicketTier queries
```

**Recommended Fix:**
Add eager loading before iteration:
```ruby
events = events.includes(:user, :ticket_tiers)
```

---

## Issue #7 — Mass Assignment of `sold_count` in TicketTiersController

| Field | Value |
|-------|-------|
| **File** | `app/controllers/api/v1/ticket_tiers_controller.rb:53` |
| **Category** | Data Integrity |
| **Severity** | MEDIUM |

**Description:**
The `tier_params` method permits `sold_count` in the strong parameters: `params.require(:ticket_tier).permit(:name, :price, :quantity, :sold_count, ...)`. This means any authenticated user can manually set the number of tickets "sold" via the API, bypassing all inventory logic. An organizer (or any user, since there's no role check) could set `sold_count` to 0 to "restock" sold-out tiers, or inflate it to fake scarcity.

**Vulnerable code:**
```ruby
# app/controllers/api/v1/ticket_tiers_controller.rb:53
def tier_params
  params.require(:ticket_tier).permit(:name, :price, :quantity, :sold_count, :sales_start, :sales_end)
  #                                                              ^^^^^^^^^^^  should not be permitted
end
```

**Recommended Fix:**
Remove `:sold_count` from `tier_params`. This field should only be modified by the `reserve_tickets!` method during order creation.

### Proof

**Step 1 — Login as Ananya (attendee, user_id=3):**
```bash
curl -s -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"ananya@example.com","password":"password123"}'
```
Response:
```json
{
  "token": "eyJhbGciOiJIUzI1NiJ9...",
  "user": { "id": 3, "name": "Ananya Gupta", "email": "ananya@example.com", "role": "attendee" }
}
```

**Step 2 — BEFORE: VIP Lounge tier (id=3) is sold out (available=0, quantity=50, sold_count=50):**
```bash
curl -s http://localhost:3000/api/v1/events/1/ticket_tiers
```
Response:
```json
[
  { "id": 1, "name": "Early Bird", "price": 999.0, "quantity": 100, "available": 2, ... },
  { "id": 2, "name": "Regular", "price": 1499.0, "quantity": 200, "available": 155, ... },
  { "id": 3, "name": "VIP Lounge", "price": 3999.0, "quantity": 50, "available": 0, ... }
]
```

**Step 3 — Ananya (an attendee!) resets sold_count to 0 via mass assignment:**
```bash
ANANYA_TOKEN="<token from step 1>"

curl -s -X PUT http://localhost:3000/api/v1/events/1/ticket_tiers/3 \
  -H "Authorization: Bearer $ANANYA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"ticket_tier":{"sold_count":0}}'
```
Response — sold_count is now 0:
```json
{
  "sold_count": 0,
  "event_id": 1,
  "price": "3999.0",
  "quantity": 50,
  "id": 3,
  "name": "VIP Lounge",
  ...
}
```

**Step 4 — AFTER: VIP Lounge now shows 50 available (was 0) — inventory is corrupted:**
```bash
curl -s http://localhost:3000/api/v1/events/1/ticket_tiers
```
Response:
```json
[
  { "id": 1, "name": "Early Bird", "price": 999.0, "quantity": 100, "available": 2, ... },
  { "id": 2, "name": "Regular", "price": 1499.0, "quantity": 200, "available": 155, ... },
  { "id": 3, "name": "VIP Lounge", "price": 3999.0, "quantity": 50, "available": 50, ... }
]
```
An **attendee** with no ownership of this event just "restocked" 50 VIP tickets by directly setting `sold_count=0`. This bypasses all inventory logic and could lead to double-selling tickets.

---

## Additional Observations (Not in Top 7)

- **User enumeration via login:** Login returns different error messages for "no account" vs "invalid password" (`auth_controller.rb:24-28`), allowing attackers to enumerate valid email addresses.
- **Synchronous email delivery:** `deliver_now` in callbacks (`event.rb:39,49`, `order.rb:54,65,67`) blocks the request thread. Should use `deliver_later`.
- **Hardcoded secret keys:** `config/secrets.yml` contains hardcoded development/test secret keys in version control.
- **No pagination:** `events#index` and `orders#index` have no pagination — will cause memory/performance issues at scale.
- **`geocode_venue` has `sleep(0.1)`:** Artificial delay in a `before_save` callback (`event.rb:31`) slows every event save.
