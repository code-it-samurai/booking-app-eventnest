# Bookmark Feature — Walkthrough & Curl Demo

This document demonstrates the full Event Bookmark (Wishlist) feature using curl commands against the running app.

---

## Prerequisites

1. App running on `http://localhost:3000`
2. Database seeded: `rails db:seed`
3. All passwords are `password123`

**Seed users:**

| User | Email | Role |
|------|-------|------|
| Priya Mehta | priya@eventnest.dev | organizer (owns events #1, #2, #5) |
| Rahul Sharma | rahul@eventnest.dev | organizer (owns events #3, #4) |
| Ananya Gupta | ananya@example.com | attendee |
| Vikram Patel | vikram@example.com | attendee |

**Seed events (published & upcoming):**

| ID | Title |
|----|-------|
| 1 | Mumbai Indie Music Festival 2025 |
| 2 | RailsConf India 2025 |
| 3 | Advanced PostgreSQL Workshop |

---

## Step 1 — Obtain Auth Tokens

### Login as Ananya (attendee)

```bash
curl -s -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"ananya@example.com","password":"password123"}'
```

Response:
```json
{
  "token": "<ANANYA_TOKEN>",
  "user": { "id": 3, "name": "Ananya Gupta", "email": "ananya@example.com", "role": "attendee" }
}
```

```bash
# Save the token for subsequent requests
ANANYA_TOKEN="<paste token from response above>"
```

### Login as Vikram (attendee)

```bash
curl -s -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"vikram@example.com","password":"password123"}'
```

Response:
```json
{
  "token": "<VIKRAM_TOKEN>",
  "user": { "id": 4, "name": "Vikram Patel", "email": "vikram@example.com", "role": "attendee" }
}
```

```bash
VIKRAM_TOKEN="<paste token from response above>"
```

### Login as Priya (organizer)

```bash
curl -s -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"priya@eventnest.dev","password":"password123"}'
```

Response:
```json
{
  "token": "<PRIYA_TOKEN>",
  "user": { "id": 1, "name": "Priya Mehta", "email": "priya@eventnest.dev", "role": "organizer" }
}
```

```bash
PRIYA_TOKEN="<paste token from response above>"
```

### Login as Rahul (organizer)

```bash
curl -s -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"rahul@eventnest.dev","password":"password123"}'
```

Response:
```json
{
  "token": "<RAHUL_TOKEN>",
  "user": { "id": 2, "name": "Rahul Sharma", "email": "rahul@eventnest.dev", "role": "organizer" }
}
```

```bash
RAHUL_TOKEN="<paste token from response above>"
```

---

## Step 2 — Attendee Creates a Bookmark (Happy Path)

### Ananya bookmarks event #1 (Mumbai Indie Music Festival)

```bash
curl -s -X POST http://localhost:3000/api/v1/events/1/bookmark \
  -H "Authorization: Bearer $ANANYA_TOKEN"
```

Expected response (201 Created):
```json
{
  "id": 1,
  "event_id": 1,
  "user_id": 3,
  "created_at": "2026-04-10T..."
}
```

### Ananya bookmarks event #2 (RailsConf India)

```bash
curl -s -X POST http://localhost:3000/api/v1/events/2/bookmark \
  -H "Authorization: Bearer $ANANYA_TOKEN"
```

Expected response (201 Created):
```json
{
  "id": 2,
  "event_id": 2,
  "user_id": 3,
  "created_at": "2026-04-10T..."
}
```

### Vikram bookmarks event #1

```bash
curl -s -X POST http://localhost:3000/api/v1/events/1/bookmark \
  -H "Authorization: Bearer $VIKRAM_TOKEN"
```

Expected response (201 Created):
```json
{
  "id": 3,
  "event_id": 1,
  "user_id": 4,
  "created_at": "2026-04-10T..."
}
```

---

## Step 3 — Duplicate Bookmark Rejected

### Ananya tries to bookmark event #1 again

```bash
curl -s -X POST http://localhost:3000/api/v1/events/1/bookmark \
  -H "Authorization: Bearer $ANANYA_TOKEN"
```

Expected response (422 Unprocessable Entity):
```json
{
  "errors": ["User has already bookmarked this event"]
}
```

---

## Step 4 — List My Bookmarks

### Ananya lists her bookmarks (should see events #1 and #2)

```bash
curl -s http://localhost:3000/api/v1/bookmarks \
  -H "Authorization: Bearer $ANANYA_TOKEN"
```

Expected response (200 OK):
```json
[
  {
    "id": 1,
    "event": {
      "id": 1,
      "title": "Mumbai Indie Music Festival 2025",
      "starts_at": "2026-05-01T...",
      "venue": "Bandra Fort Amphitheatre, Mumbai",
      "city": "Mumbai"
    },
    "created_at": "2026-04-10T..."
  },
  {
    "id": 2,
    "event": {
      "id": 2,
      "title": "RailsConf India 2025",
      "starts_at": "2026-05-15T...",
      "venue": "Bengaluru International Exhibition Centre, Bengaluru",
      "city": "Bengaluru"
    },
    "created_at": "2026-04-10T..."
  }
]
```

### Vikram lists his bookmarks (should see only event #1)

```bash
curl -s http://localhost:3000/api/v1/bookmarks \
  -H "Authorization: Bearer $VIKRAM_TOKEN"
```

Expected response (200 OK):
```json
[
  {
    "id": 3,
    "event": {
      "id": 1,
      "title": "Mumbai Indie Music Festival 2025",
      "starts_at": "2026-05-01T...",
      "venue": "Bandra Fort Amphitheatre, Mumbai",
      "city": "Mumbai"
    },
    "created_at": "2026-04-10T..."
  }
]
```

---

## Step 5 — Organizer Views Bookmark Count

### Priya (organizer, owns event #1) checks bookmark count

Event #1 has been bookmarked by both Ananya and Vikram, so the count should be 2.

```bash
curl -s http://localhost:3000/api/v1/events/1/bookmark_count \
  -H "Authorization: Bearer $PRIYA_TOKEN"
```

Expected response (200 OK):
```json
{
  "event_id": 1,
  "bookmark_count": 2
}
```

### Priya checks bookmark count for event #2

Event #2 has been bookmarked by only Ananya, so the count should be 1.

```bash
curl -s http://localhost:3000/api/v1/events/2/bookmark_count \
  -H "Authorization: Bearer $PRIYA_TOKEN"
```

Expected response (200 OK):
```json
{
  "event_id": 2,
  "bookmark_count": 1
}
```

---

## Step 6 — Authorization: Attendee Forbidden from Viewing Bookmark Count

### Ananya tries to view bookmark count

```bash
curl -s http://localhost:3000/api/v1/events/1/bookmark_count \
  -H "Authorization: Bearer $ANANYA_TOKEN"
```

Expected response (403 Forbidden):
```json
{
  "error": "Only the event organizer can view bookmark counts"
}
```

---

## Step 7 — Authorization: Non-Owner Organizer Forbidden from Viewing Bookmark Count

### Rahul (organizer, but does NOT own event #1) tries to view count

```bash
curl -s http://localhost:3000/api/v1/events/1/bookmark_count \
  -H "Authorization: Bearer $RAHUL_TOKEN"
```

Expected response (403 Forbidden):
```json
{
  "error": "Only the event organizer can view bookmark counts"
}
```

---

## Step 8 — Authorization: Organizer Forbidden from Creating Bookmarks

### Priya (organizer) tries to bookmark an event

```bash
curl -s -X POST http://localhost:3000/api/v1/events/1/bookmark \
  -H "Authorization: Bearer $PRIYA_TOKEN"
```

Expected response (403 Forbidden):
```json
{
  "error": "Only attendees can bookmark events"
}
```

---

## Step 9 — Remove a Bookmark

### Ananya removes her bookmark on event #1

```bash
curl -s -X DELETE http://localhost:3000/api/v1/events/1/bookmark \
  -H "Authorization: Bearer $ANANYA_TOKEN" \
  -w "\nHTTP Status: %{http_code}\n"
```

Expected response (204 No Content):
```
HTTP Status: 204
```

### Verify: Ananya's bookmarks now show only event #2

```bash
curl -s http://localhost:3000/api/v1/bookmarks \
  -H "Authorization: Bearer $ANANYA_TOKEN"
```

Expected response (200 OK):
```json
[
  {
    "id": 2,
    "event": {
      "id": 2,
      "title": "RailsConf India 2025",
      ...
    },
    "created_at": "2026-04-10T..."
  }
]
```

### Verify: Bookmark count for event #1 drops to 1 (only Vikram's remains)

```bash
curl -s http://localhost:3000/api/v1/events/1/bookmark_count \
  -H "Authorization: Bearer $PRIYA_TOKEN"
```

Expected response (200 OK):
```json
{
  "event_id": 1,
  "bookmark_count": 1
}
```

---

## Step 10 — Remove Nonexistent Bookmark Returns 404

### Ananya tries to remove the bookmark she already removed

```bash
curl -s -X DELETE http://localhost:3000/api/v1/events/1/bookmark \
  -H "Authorization: Bearer $ANANYA_TOKEN"
```

Expected response (404 Not Found):
```json
{
  "error": "Bookmark not found"
}
```

---

## Step 11 — Cannot Remove Another User's Bookmark

### Ananya tries to remove Vikram's bookmark on event #1

Vikram still has a bookmark on event #1. Ananya does not — so `DELETE` scoped to `current_user.bookmarks` will not find it.

```bash
curl -s -X DELETE http://localhost:3000/api/v1/events/1/bookmark \
  -H "Authorization: Bearer $ANANYA_TOKEN"
```

Expected response (404 Not Found):
```json
{
  "error": "Bookmark not found"
}
```

Vikram's bookmark is still intact:

```bash
curl -s http://localhost:3000/api/v1/bookmarks \
  -H "Authorization: Bearer $VIKRAM_TOKEN"
```

Expected response (200 OK) — event #1 still bookmarked:
```json
[
  {
    "id": 3,
    "event": { "id": 1, "title": "Mumbai Indie Music Festival 2025", ... },
    ...
  }
]
```

---

## Step 12 — Bookmark Nonexistent Event Returns 404

```bash
curl -s -X POST http://localhost:3000/api/v1/events/999999/bookmark \
  -H "Authorization: Bearer $ANANYA_TOKEN"
```

Expected response (404 Not Found):
```json
{
  "status": 404,
  "error": "Not Found"
}
```

---

## Step 13 — Unauthenticated Request Returns 401

```bash
curl -s -X POST http://localhost:3000/api/v1/events/1/bookmark
```

Expected response (401 Unauthorized):
```json
{
  "error": "Unauthorized"
}
```

---

## API Endpoint Summary

| Method | Endpoint | Auth | Role | Description |
|--------|----------|------|------|-------------|
| POST | `/api/v1/events/:event_id/bookmark` | Required | Attendee only | Bookmark an event |
| DELETE | `/api/v1/events/:event_id/bookmark` | Required | Bookmark owner | Remove a bookmark |
| GET | `/api/v1/bookmarks` | Required | Any | List my bookmarks |
| GET | `/api/v1/events/:event_id/bookmark_count` | Required | Event organizer only | View bookmark count |

---

## Test Suite

Run the full suite to verify all bookmark tests pass:

```bash
bundle exec rspec
```

Expected: **47 examples, 0 failures**

Bookmark-specific tests:

```bash
bundle exec rspec spec/controllers/bookmarks_controller_spec.rb spec/models/bookmark_spec.rb
```

Expected: **16 examples, 0 failures**
