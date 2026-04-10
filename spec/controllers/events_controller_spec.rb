require "rails_helper"

RSpec.describe Api::V1::EventsController, type: :request do
  let(:organizer) { create(:user, :organizer) }
  let(:attendee) { create(:user) }

  def auth_headers(user)
    token = user.generate_jwt
    { "Authorization" => "Bearer #{token}" }
  end

  describe "GET /api/v1/events" do
    it "returns published upcoming events" do
      create(:event, status: "published", starts_at: 1.week.from_now, ends_at: 1.week.from_now + 3.hours)
      create(:event, status: "draft", starts_at: 2.weeks.from_now, ends_at: 2.weeks.from_now + 3.hours)

      get "/api/v1/events"

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data.length).to eq(1)
    end

    it "searches events safely without SQL injection" do
      create(:event, title: "Ruby Conference", status: "published", starts_at: 1.week.from_now, ends_at: 1.week.from_now + 3.hours)
      create(:event, title: "Secret Draft Event", status: "draft", starts_at: 2.weeks.from_now, ends_at: 2.weeks.from_now + 3.hours)

      # SQL injection payload that would bypass filters if interpolated directly
      get "/api/v1/events", params: { search: "') OR 1=1 --" }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      # Should return 0 results because no event title/description contains this literal string
      # Before the fix, this would return ALL events (including drafts) via SQL injection
      expect(data.length).to eq(0)
    end

    it "returns matching events for legitimate search terms" do
      create(:event, title: "Ruby Conference", status: "published", starts_at: 1.week.from_now, ends_at: 1.week.from_now + 3.hours)
      create(:event, title: "Python Workshop", status: "published", starts_at: 2.weeks.from_now, ends_at: 2.weeks.from_now + 3.hours)

      get "/api/v1/events", params: { search: "Ruby" }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data.length).to eq(1)
      expect(data[0]["title"]).to eq("Ruby Conference")
    end
  end

  describe "POST /api/v1/events" do
    it "creates an event" do
      event_params = {
        event: {
          title: "Test Event",
          description: "A test event",
          venue: "Test Venue, Mumbai",
          starts_at: 1.week.from_now,
          ends_at: 1.week.from_now + 3.hours,
          category: "conference"
        }
      }

      post "/api/v1/events", params: event_params, headers: auth_headers(attendee)

      expect(response).to have_http_status(:created)
    end
  end

  describe "PUT /api/v1/events/:id" do
    it "updates an event" do
      event = create(:event, user: organizer)

      put "/api/v1/events/#{event.id}",
        params: { event: { title: "Updated Title" } },
        headers: auth_headers(organizer)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "DELETE /api/v1/events/:id" do
    it "deletes an event" do
      event = create(:event, user: organizer)

      delete "/api/v1/events/#{event.id}", headers: auth_headers(organizer)

      expect(response).to have_http_status(:no_content)
    end
  end
end
