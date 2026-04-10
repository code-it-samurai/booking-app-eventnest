require "rails_helper"

RSpec.describe Api::V1::BookmarksController, type: :request do
  let(:organizer) { create(:user, :organizer) }
  let(:attendee) { create(:user) }
  let(:attendee2) { create(:user) }
  let(:event) { create(:event, user: organizer, status: "published", starts_at: 2.weeks.from_now, ends_at: 2.weeks.from_now + 3.hours) }

  def auth_headers(user)
    token = user.generate_jwt
    { "Authorization" => "Bearer #{token}" }
  end

  describe "POST /api/v1/events/:event_id/bookmark" do
    it "creates a bookmark for an attendee" do
      post "/api/v1/events/#{event.id}/bookmark", headers: auth_headers(attendee)

      expect(response).to have_http_status(:created)
      data = JSON.parse(response.body)
      expect(data["event_id"]).to eq(event.id)
      expect(data["user_id"]).to eq(attendee.id)
    end

    it "rejects duplicate bookmarks" do
      create(:bookmark, user: attendee, event: event)

      post "/api/v1/events/#{event.id}/bookmark", headers: auth_headers(attendee)

      expect(response).to have_http_status(:unprocessable_entity)
      data = JSON.parse(response.body)
      expect(data["errors"]).to include("User has already bookmarked this event")
    end

    it "forbids organizers from bookmarking" do
      post "/api/v1/events/#{event.id}/bookmark", headers: auth_headers(organizer)

      expect(response).to have_http_status(:forbidden)
      data = JSON.parse(response.body)
      expect(data["error"]).to eq("Only attendees can bookmark events")
    end

    it "returns 404 for non-existent event" do
      post "/api/v1/events/999999/bookmark", headers: auth_headers(attendee)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/events/:event_id/bookmark" do
    it "removes a bookmark" do
      create(:bookmark, user: attendee, event: event)

      delete "/api/v1/events/#{event.id}/bookmark", headers: auth_headers(attendee)

      expect(response).to have_http_status(:no_content)
      expect(Bookmark.where(user: attendee, event: event)).to be_empty
    end

    it "returns 404 when bookmark does not exist" do
      delete "/api/v1/events/#{event.id}/bookmark", headers: auth_headers(attendee)

      expect(response).to have_http_status(:not_found)
    end

    it "does not remove another user's bookmark" do
      create(:bookmark, user: attendee2, event: event)

      delete "/api/v1/events/#{event.id}/bookmark", headers: auth_headers(attendee)

      expect(response).to have_http_status(:not_found)
      expect(Bookmark.where(user: attendee2, event: event)).to exist
    end
  end

  describe "GET /api/v1/bookmarks" do
    it "lists the current user's bookmarks" do
      event2 = create(:event, user: organizer, status: "published", starts_at: 3.weeks.from_now, ends_at: 3.weeks.from_now + 3.hours)
      create(:bookmark, user: attendee, event: event)
      create(:bookmark, user: attendee, event: event2)
      create(:bookmark, user: attendee2, event: event)

      get "/api/v1/bookmarks", headers: auth_headers(attendee)

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data.length).to eq(2)
      expect(data.map { |b| b["event"]["id"] }).to contain_exactly(event.id, event2.id)
    end

    it "returns empty array when no bookmarks" do
      get "/api/v1/bookmarks", headers: auth_headers(attendee)

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data).to eq([])
    end
  end

  describe "GET /api/v1/events/:event_id/bookmark_count" do
    it "returns bookmark count for the event organizer" do
      create(:bookmark, user: attendee, event: event)
      create(:bookmark, user: attendee2, event: event)

      get "/api/v1/events/#{event.id}/bookmark_count", headers: auth_headers(organizer)

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["bookmark_count"]).to eq(2)
    end

    it "forbids attendees from seeing bookmark counts" do
      get "/api/v1/events/#{event.id}/bookmark_count", headers: auth_headers(attendee)

      expect(response).to have_http_status(:forbidden)
    end

    it "forbids organizers who don't own the event" do
      other_organizer = create(:user, :organizer)

      get "/api/v1/events/#{event.id}/bookmark_count", headers: auth_headers(other_organizer)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
