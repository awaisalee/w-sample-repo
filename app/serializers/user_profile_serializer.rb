class UserProfileSerializer < ActiveModel::Serializer
  attributes :id,
             :name,
             :status,
             :bio,
             :category_id,
             :user_id,
             :facebook_handle,
             :instagram_handle,
             :twitter_handle,
             :youtube_handle,
             :discord_handle,
             :twitch_handle,
             :telegram_handle

  belongs_to :user
  belongs_to :category
end
