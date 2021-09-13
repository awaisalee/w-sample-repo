class UserSerializer < ActiveModel::Serializer
  attributes :id,
             :uid,
             :room_id,
             :provider,
             :username,
             :email,
             :social_uid,
             :image,
             :brand_image,
             :language,
             :deleted,
             :timezone,
             :account_type,
             :business_name,
             :no_of_licenses,
             :first_name,
             :last_name,
             :phone_number,
             :business_role,
             :google_contact_sync_time,
             :integrated_google_calendar,
             :integrated_google_contact,
             :whistle_plus_trial_ended,
             :theme_colors

  has_one :user_profile
  has_one :availability
  has_many :rooms
end
