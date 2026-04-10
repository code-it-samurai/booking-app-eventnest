Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      post "auth/register", to: "auth#register"
      post "auth/login", to: "auth#login"

      resources :events do
        resources :ticket_tiers, only: [:index, :create, :update, :destroy]
        resource :bookmark, only: [:create, :destroy]
        get :bookmark_count, to: "bookmarks#count"
      end

      resources :bookmarks, only: [:index]

      resources :orders, only: [:index, :show, :create] do
        member do
          post :cancel
        end
      end
    end
  end
end
