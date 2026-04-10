# Terminal Log — EventNest Assessment

---

## 1. Setup Commands and Output

```bash
$ bundle install
Bundle complete! 20 Gemfile dependencies, 103 gems now installed.

$ rails db:create db:migrate db:seed
Created database 'eventnest_development'
Created database 'eventnest_test'
Seeding database...
  Bookmark: Ananya Gupta -> Mumbai Indie Music Festival 2025
  Bookmark: Ananya Gupta -> Advanced PostgreSQL Workshop
  Bookmark: Vikram Patel -> RailsConf India 2025
  Bookmark: Vikram Patel -> Mumbai Indie Music Festival 2025
  Bookmark: Sneha Reddy -> Advanced PostgreSQL Workshop
  Bookmark: Sneha Reddy -> RailsConf India 2025
Seeded: 5 users, 5 events, 7 tiers, 4 orders, 6 bookmarks

$ rails server -p 3000
=> Booting Puma
=> Rails 7.1.6 application starting in development
```

---

## 2. Initial Test Suite Run (Before Changes)

Before any code changes, the original codebase had 29 specs. Two failed due to missing Redis (CRM sync callback), 27 passed:

```
$ bundle exec rspec
...................FF........

Finished in 1.12 seconds
29 examples, 2 failures

Failed examples:
rspec ./spec/models/order_spec.rb:19 # Order#confirm! sets status to confirmed
rspec ./spec/models/order_spec.rb:27 # Order#cancel! sets status to cancelled
```

The 2 failures are pre-existing — `Order#confirm!` and `Order#cancel!` trigger `CrmSyncJob.perform_later` which tries to connect to Redis/Sidekiq. With Redis running, these also pass.

---

## 3. Bug Proof — curl Commands + Responses

### Bug 1: SQL Injection in Event Search (Issue #1 from REVIEW.md)

**File:** `app/controllers/api/v1/events_controller.rb:10`

The search parameter was interpolated directly into SQL: `"title LIKE '%#{params[:search]}%'"`.

#### Normal search (baseline — 3 published upcoming events):

```bash
$ curl -s "http://localhost:3000/api/v1/events" | python3 -c "
import sys,json
data=json.load(sys.stdin)
print(f'Total: {len(data)} events')
for e in data: print(f'  - id={e[\"id\"]}, title={e[\"title\"]}')"
```

```
Total: 3 events
  - id=3, title=Advanced PostgreSQL Workshop
  - id=1, title=Mumbai Indie Music Festival 2025
  - id=2, title=RailsConf India 2025
```

#### SQL Injection (BEFORE fix) — bypasses published/upcoming filters:

```bash
$ curl -s "http://localhost:3000/api/v1/events?search=%27)%20OR%201%3D1%20--" | python3 -c "
import sys,json
data=json.load(sys.stdin)
print(f'Total: {len(data)} events')
for e in data: print(f'  - id={e[\"id\"]}, title={e[\"title\"]}')"
```

```
Total: 5 events
  - id=1, title=Mumbai Indie Music Festival 2025
  - id=2, title=RailsConf India 2025
  - id=3, title=Advanced PostgreSQL Workshop
  - id=4, title=Untitled Yoga Retreat          ← DRAFT event (should be hidden)
  - id=5, title=Diwali Night Market 2024       ← PAST event (should be hidden)
```

The injected `') OR 1=1 --` bypassed both the `published` and `upcoming` scope filters.

---

### Bug 2: Unauthorized Order Access (Issue #2 from REVIEW.md)

**File:** `app/controllers/api/v1/orders_controller.rb:6`

`Order.all` returns every order in the system regardless of who's logged in.

#### Setup — Login as Vikram (attendee, user_id=4):

```bash
$ curl -s -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"vikram@example.com","password":"password123"}'
```

```json
{
  "token": "eyJhbGciOiJIUzI1NiJ9...",
  "user": { "id": 4, "name": "Vikram Patel", "email": "vikram@example.com", "role": "attendee" }
}
```

#### Vikram sees ALL 4 orders (should only see his own order #2):

```bash
$ curl -s http://localhost:3000/api/v1/orders \
  -H "Authorization: Bearer $VIKRAM_TOKEN"
```

```json
[
  { "id": 4, "confirmation_number": "EVN-M3N4O5P6", "event": "RailsConf India 2025", "status": "cancelled", "total_amount": 2499.0, "items_count": 1 },
  { "id": 3, "confirmation_number": "EVN-I9J0K1L2", "event": "Advanced PostgreSQL Workshop", "status": "pending", "total_amount": 1999.0, "items_count": 1 },
  { "id": 2, "confirmation_number": "EVN-E5F6G7H8", "event": "RailsConf India 2025", "status": "confirmed", "total_amount": 4999.0, "items_count": 1 },
  { "id": 1, "confirmation_number": "EVN-A1B2C3D4", "event": "Mumbai Indie Music Festival 2025", "status": "confirmed", "total_amount": 2998.0, "items_count": 1 }
]
```

#### Vikram views Ananya's order #1 with payment details:

```bash
$ curl -s http://localhost:3000/api/v1/orders/1 \
  -H "Authorization: Bearer $VIKRAM_TOKEN"
```

```json
{
  "id": 1,
  "confirmation_number": "EVN-A1B2C3D4",
  "status": "confirmed",
  "total_amount": 2998.0,
  "event": { "id": 1, "title": "Mumbai Indie Music Festival 2025", "starts_at": "2026-05-01T02:20:59.922Z" },
  "items": [{ "ticket_tier": "Regular", "quantity": 2, "unit_price": 1499.0, "subtotal": 2998.0 }],
  "payment": { "status": "completed", "provider_reference": "ch_abc123def456" }
}
```

Vikram can see Ananya's full order including the Stripe payment reference — a clear data privacy violation.

---

## 4. Fix Proof — Same curl Commands After Fix

### SQL Injection Fix

**Change:** Replaced raw string interpolation with parameterized query + `sanitize_sql_like` in `events_controller.rb:10`.

```ruby
# BEFORE (vulnerable)
events = events.where("title LIKE '%#{params[:search]}%' OR description LIKE '%#{params[:search]}%'")

# AFTER (safe)
search_term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:search])}%"
events = events.where("title LIKE ? OR description LIKE ?", search_term, search_term)
```

#### Same SQL injection payload — now returns empty (treated as literal text):

```bash
$ curl -s "http://localhost:3000/api/v1/events?search=%27)%20OR%201%3D1%20--"
```

```json
[]
```

#### Legitimate search still works:

```bash
$ curl -s "http://localhost:3000/api/v1/events?search=PostgreSQL"
```

```json
[
  {
    "id": 3,
    "title": "Advanced PostgreSQL Workshop",
    "description": "Hands-on workshop covering advanced PostgreSQL features.",
    "venue": "WeWork BKC, Mumbai",
    "city": "Mumbai",
    "starts_at": "2026-04-24T02:20:59.957Z",
    "ends_at": "2026-04-24T10:20:59.957Z",
    "category": "workshop",
    "organizer": "Rahul Sharma",
    "total_tickets": 40,
    "tickets_sold": 38,
    "ticket_tiers": [{ "id": 7, "name": "Workshop Seat", "price": 1999.0, "available": 2 }]
  }
]
```

---

## 5. Feature Demo — Bookmark Feature curl Commands

### Setup — Get auth tokens:

```bash
$ curl -s -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"ananya@example.com","password":"password123"}'
# → ANANYA_TOKEN (attendee, user_id=3)

$ curl -s -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"priya@eventnest.dev","password":"password123"}'
# → PRIYA_TOKEN (organizer, user_id=1, owns events #1, #2, #5)
```

### Create a bookmark:

```bash
$ curl -s -X POST http://localhost:3000/api/v1/events/1/bookmark \
  -H "Authorization: Bearer $ANANYA_TOKEN"
```

```json
{
  "id": 7,
  "event_id": 1,
  "user_id": 3,
  "created_at": "2026-04-10T02:22:02.746Z"
}
```

### Duplicate bookmark rejected:

```bash
$ curl -s -X POST http://localhost:3000/api/v1/events/1/bookmark \
  -H "Authorization: Bearer $ANANYA_TOKEN"
```

```json
{
  "errors": ["User has already bookmarked this event"]
}
```

### List my bookmarks:

```bash
$ curl -s http://localhost:3000/api/v1/bookmarks \
  -H "Authorization: Bearer $ANANYA_TOKEN"
```

```json
[
  {
    "id": 7,
    "event": {
      "id": 1,
      "title": "Mumbai Indie Music Festival 2025",
      "starts_at": "2026-05-01T02:20:59.922Z",
      "venue": "Bandra Fort Amphitheatre, Mumbai",
      "city": "Mumbai"
    },
    "created_at": "2026-04-10T02:22:02.746Z"
  }
]
```

### Organizer views bookmark count:

```bash
$ curl -s http://localhost:3000/api/v1/events/1/bookmark_count \
  -H "Authorization: Bearer $PRIYA_TOKEN"
```

```json
{
  "event_id": 1,
  "bookmark_count": 2
}
```

### Attendee forbidden from viewing count:

```bash
$ curl -s http://localhost:3000/api/v1/events/1/bookmark_count \
  -H "Authorization: Bearer $ANANYA_TOKEN"
```

```json
{
  "error": "Only the event organizer can view bookmark counts"
}
```

### Organizer forbidden from bookmarking:

```bash
$ curl -s -X POST http://localhost:3000/api/v1/events/1/bookmark \
  -H "Authorization: Bearer $PRIYA_TOKEN"
```

```json
{
  "error": "Only attendees can bookmark events"
}
```

### Remove a bookmark:

```bash
$ curl -s -X DELETE http://localhost:3000/api/v1/events/1/bookmark \
  -H "Authorization: Bearer $ANANYA_TOKEN" -w "\nHTTP Status: %{http_code}\n"
```

```
HTTP Status: 204
```

---

## 6. Final Test Suite Run — All Tests Passing

```
$ bundle exec rspec

....................................2026-04-10T02:21:08.437Z pid=94956 tid=223g INFO: Sidekiq 7.3.9
..........

Finished in 1.3 seconds (files took 0.77146 seconds to load)
47 examples, 0 failures
```

All 47 tests pass:
- 6 original events controller specs (including 2 new SQL injection tests)
- 3 original orders controller specs
- 5 original event model specs
- 4 original order model specs
- 3 original ticket tier model specs
- 14 bookmark controller specs
- 2 bookmark model specs
- 6 original event model specs
- 4 original order model specs
