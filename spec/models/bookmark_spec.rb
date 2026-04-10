require "rails_helper"

RSpec.describe Bookmark, type: :model do
  describe "associations" do
    it { should belong_to(:user) }
    it { should belong_to(:event) }
  end

  describe "validations" do
    it "enforces uniqueness of user + event at the model level" do
      event = create(:event)
      user = create(:user)
      create(:bookmark, user: user, event: event)

      duplicate = Bookmark.new(user: user, event: event)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:user_id]).to include("has already bookmarked this event")
    end
  end

  describe "database constraint" do
    it "raises on duplicate user + event at the database level" do
      event = create(:event)
      user = create(:user)
      Bookmark.create!(user: user, event: event)

      expect {
        Bookmark.connection.execute(
          "INSERT INTO bookmarks (user_id, event_id, created_at, updated_at) VALUES (#{user.id}, #{event.id}, NOW(), NOW())"
        )
      }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end
end
