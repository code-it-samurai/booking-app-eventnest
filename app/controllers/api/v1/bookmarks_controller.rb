module Api
  module V1
    class BookmarksController < ApplicationController
      def index
        bookmarks = current_user.bookmarks.includes(:event)

        render json: bookmarks.map { |bookmark|
          {
            id: bookmark.id,
            event: {
              id: bookmark.event.id,
              title: bookmark.event.title,
              starts_at: bookmark.event.starts_at,
              venue: bookmark.event.venue,
              city: bookmark.event.city
            },
            created_at: bookmark.created_at
          }
        }
      end

      def create
        unless current_user.attendee?
          return render json: { error: "Only attendees can bookmark events" }, status: :forbidden
        end

        event = Event.find(params[:event_id])
        bookmark = current_user.bookmarks.build(event: event)

        if bookmark.save
          render json: {
            id: bookmark.id,
            event_id: bookmark.event_id,
            user_id: bookmark.user_id,
            created_at: bookmark.created_at
          }, status: :created
        else
          render json: { errors: bookmark.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        bookmark = current_user.bookmarks.find_by!(event_id: params[:event_id])
        bookmark.destroy
        head :no_content
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Bookmark not found" }, status: :not_found
      end

      def count
        event = Event.find(params[:event_id])

        unless current_user.organizer? && event.user_id == current_user.id
          return render json: { error: "Only the event organizer can view bookmark counts" }, status: :forbidden
        end

        render json: { event_id: event.id, bookmark_count: event.bookmarks.count }
      end
    end
  end
end
