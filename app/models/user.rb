# frozen_string_literal: true

# BigBlueButton open source conferencing system - http://www.bigbluebutton.org/.
#
# Copyright (c) 2018 BigBlueButton Inc. and by respective authors (see below).
#
# This program is free software; you can redistribute it and/or modify it under the
# terms of the GNU Lesser General Public License as published by the Free Software
# Foundation; either version 3.0 of the License, or (at your option) any later
# version.
#
# BigBlueButton is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License along
# with BigBlueButton; if not, see <http://www.gnu.org/licenses/>.

require 'bbb_api'

class User < ApplicationRecord
  include Deleteable
  include Emailer

  cattr_accessor :current_user

  after_create :setup_user
  before_create :set_default_branding

  before_save { email.try(:downcase!) }

  before_destroy :destroy_appointments
  before_destroy :destroy_rooms

  enum account_type: { personal: 0, business: 1 }

  has_many :rooms
  has_many :shared_access
  has_many :appointments, dependent: :destroy
  has_many :recent_rooms, dependent: :destroy
  belongs_to :main_room, class_name: 'Room', foreign_key: :room_id, required: false

  has_and_belongs_to_many :roles, join_table: :users_roles # obsolete

  belongs_to :role, required: false
  has_one :subscription, dependent: :destroy
  has_one :user_profile, dependent: :destroy
  has_many :monthly_sessions, dependent: :destroy

  belongs_to :manager, class_name: 'User', optional: true
  has_many :co_hosts, class_name: 'User', foreign_key: 'manager_id'
  has_many :google_contacts, dependent: :destroy

  has_one :availability

  validates :provider, presence: true
  has_many :tokens, dependent: :destroy

  validates :last_name, length: { maximum: 256 }, presence: true,
                   format: { without: %r{https?://}i }
  validates :first_name, length: { maximum: 256 }, presence: true,
                   format: { without: %r{https?://}i }, on: :create
  validate :check_if_email_can_be_blank
  validates :email, length: { maximum: 256 }, allow_blank: false,
                    uniqueness: { case_sensitive: false },
                    format: { with: /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i }
  validates :business_name, length: { maximum: 256 }, presence: true,
                   format: { without: %r{https?://}i }, if: :business?, on: :create

  validates :password, length: { minimum: 6 }, confirmation: true, if: :greenlight_account?, on: :create

  # Bypass validation if omniauth
  validates :accepted_terms, acceptance: true,
                             unless: -> { !greenlight_account? || !Rails.configuration.terms }

  # We don't want to require password validations on all accounts.
  has_secure_password(validations: false)

  # store users brand image
  mount_uploader :brand_image_attachment, UserBrandImageUploader

  def google_token
    tokens.find_by(provider: 'google')
  end

  def google_contact_token
    tokens.find_by(provider: 'google_contact')
  end

  def google_calendar_token
    tokens.find_by(provider: 'google_calendar')
  end

  def put_on_trial
    pre_registered_user = RegisteredEmail.find_by_email(email.try(:downcase!))
    RegisteredEmail.create!(:email => email.try(:downcase!)) unless pre_registered_user
    self.created_at = pre_registered_user.created_at if pre_registered_user
  end

  def remaining_monthly_sessions
    today = DateTime.now
    month = today.month
    year = today.year
    monthly_sessions = self.monthly_sessions.where(:month => month, :year => year)

    if monthly_sessions.count > 0
      current_monthly_session = monthly_sessions.first
    else
      current_monthly_session = nil
    end

    if current_monthly_session.nil?
      session = create_monthly_session(self)
      return session.available_sessions
    elsif current_monthly_session
      return current_monthly_session.available_sessions
    else
      puts "not the case right now"
    end
  end

  def has_monthly_sessions?
    return remaining_monthly_sessions > 0 unless subscribed?
    true
  end

  def decrease_monthly_sessions
    today = DateTime.now
    month = today.month
    year = today.year
    sessions = monthly_sessions.where(:month => month, :year => year)
    if sessions.count > 0 && remaining_monthly_sessions > 0
      current_monthly_session = sessions.first
      current_monthly_session.available_sessions = current_monthly_session.available_sessions - 1
      current_monthly_session.save!
    end

    # send mail after 2 session left
    if remaining_monthly_sessions == 2
      send_sessions_left_reminder_email(self)
    end

    # send mail for upgrade account if no session available
    if remaining_monthly_sessions == 0
      send_upgrade_account_email(self)
    end
  end

  def subscribed?
    return manager.subscribed? if manager.present?
    if subscription && subscription.active
      return true
    end
    false
  end

  def subscribe_plan
    return manager.subscription&.plan if manager.present?
    return subscription.plan if subscription.present?
    nil
  end

  def manager?
    manager.nil?
  end

  def full_name
    "#{first_name} #{last_name}".strip
  end

  def name
    full_name
  end

  def avatar_name
    "#{(first_name || '').strip.first}#{(last_name || '').strip.first}".strip.upcase
  end

  def plan_name
    subscribe_plan.plan_type
  rescue
    'whistle_community'
  end

  def business_name_to_group_id
    sub_business.gsub(/\s+/, "_").downcase
  rescue
    ""
  end

  def plan_subscription
    return subscription if manager?
    manager.subscription
  end

  def sub_business
    return business_name if manager?
    manager.business_name
  end

  def room_uid
    main_room&.uid
  end

  def brand_image_url
    if brand_image_attachment.url.present?
      brand_image_attachment.url
    else
      brand_image
    end
  end

  class << self
    include AuthValues

    # Generates a user from omniauth.
    def from_omniauth(auth)
      # Provider is the customer name if in loadbalanced config mode
      provider = auth['provider'] == "bn_launcher" ? auth['info']['customer'] : auth['provider']
      find_or_initialize_by(email: auth_email(auth)).tap do |u|
        u.social_uid = auth['uid']
        u.provider = provider
        u.last_name = auth_name(auth) unless u.last_name.present?
        u.first_name = auth_first_name(auth) unless u.first_name.present?
        u.username = auth_username(auth) unless u.username.present?
        u.image = auth_image(auth) unless u.image.present?
        u.business_name = u.auth_business unless u.business_name.present?
        auth_roles(u, auth)
        u.email_verified = true
        u.save!
        u.set_role :user
      end
    end

    def find_or_simulate(payload)
      find_or_initialize_by(email: payload["email"]).tap do |u|
        u.provider = "auth0"
        u.social_uid = payload["sub"]
        u.auth0_uid = payload["sub"]
        u.last_name = payload["nickname"] unless u.last_name.present?
        u.first_name = payload["nickname"] unless u.first_name.present?
        u.username = payload["nickname"] unless u.username.present?
        u.image = payload["picture"] unless u.image.present?
        u.save!

        # activate auth0 local user instance
        u.activate
      end
    end
  end

  def self.admins_search(string)
    return all if string.blank?

    active_database = Rails.configuration.database_configuration[Rails.env]["adapter"]
    # Postgres requires created_at to be cast to a string
    created_at_query = if active_database == "postgresql"
      "created_at::text"
    else
      "created_at"
    end

    search_query = "users.first_name LIKE :search OR users.last_name LIKE :search OR email LIKE :search OR username LIKE :search" \
                  " OR users.#{created_at_query} LIKE :search OR users.provider LIKE :search" \
                  " OR roles.name LIKE :search"

    search_param = "%#{sanitize_sql_like(string)}%"
    where(search_query, search: search_param)
  end

  def self.admins_order(column, direction)
    # Arel.sql to avoid sql injection
    order(Arel.sql("users.#{column} #{direction}"))
  end

  # Returns a list of rooms ordered by last session (with nil rooms last)
  def ordered_rooms
    [main_room] + rooms.where.not(id: main_room.id).order(Arel.sql("last_session IS NULL, last_session desc"))
  end

  # Activates an account and initialize a users main room
  def activate
    set_role :user if role_id.nil?
    update_attributes(email_verified: true, activated_at: Time.zone.now, activation_digest: nil)
  end

  def activated?
    Rails.configuration.enable_email_verification ? email_verified : true
  end

  def self.hash_token(token)
    Digest::SHA2.hexdigest(token)
  end

  # Sets the password reset attributes.
  def create_reset_digest
    new_token = SecureRandom.urlsafe_base64
    update_attributes(reset_digest: User.hash_token(new_token), reset_sent_at: Time.zone.now)
    new_token
  end

  def destroy_reset_digest
    update_attributes(reset_digest: nil, reset_sent_at: nil)
  end

  def create_activation_token
    new_token = SecureRandom.urlsafe_base64
    update_attribute('activation_digest', User.hash_token(new_token))
    new_token
  end

  # Return true if password reset link expires
  def password_reset_expired?
    reset_sent_at < 2.hours.ago rescue true
  end

  # Retrieves a list of rooms that are shared with the user
  def shared_rooms
    Room.where(id: shared_access.pluck(:room_id))
  end

  def name_chunk
    charset = ("a".."z").to_a - %w(b i l o s) + ("2".."9").to_a - %w(5 8)
    chunk = full_name.parameterize[0...3]
    if chunk.empty?
      chunk + (0...3).map { charset.to_a[rand(charset.size)] }.join
    elsif chunk.length == 1
      chunk + (0...2).map { charset.to_a[rand(charset.size)] }.join
    elsif chunk.length == 2
      chunk + (0...1).map { charset.to_a[rand(charset.size)] }.join
    else
      chunk
    end
  end

  def greenlight_account?
    social_uid.nil?
  end

  def admin_of?(user, permission)
    has_correct_permission = role.get_permission(permission) && id != user.id

    return has_correct_permission unless Rails.configuration.loadbalanced_configuration
    return id != user.id if has_role? :super_admin
    has_correct_permission && provider == user.provider && !user.has_role?(:super_admin)
  end

  # role functions
  def set_role(role) # rubocop:disable Naming/AccessorMethodName
    return if has_role?(role)

    new_role = Role.find_by(name: role, provider: role_provider)

    return if new_role.nil?
    create_home_room if main_room.nil? && new_role.get_permission("can_create_rooms")

    update_attribute(:role, new_role)

    new_role
  end

  # This rule is disabled as the function name must be has_role?
  def has_role?(role_name) # rubocop:disable Naming/PredicateName
    role&.name == role_name.to_s
  end

  def rollified?
    role.present?
  end

  def self.with_role(role)
    User.includes(:role).where(roles: { name: role })
  end

  def self.without_role(role)
    User.includes(:role).where.not(roles: { name: role })
  end

  def create_home_room
    room = Room.create!(owner: self, name: I18n.t("home_room"))
    update_attributes(main_room: room)
  end

  def remaining_trial_days
    time_diff = (Time.current - created_at)
    trial_period = ENV['TRIAL_PERIOD'].to_i
    diff = trial_period - (time_diff / 1.day).round
    diff <= trial_period ? diff : 0
  end

  def valid_trial
    remaining_trial_days >= 1
  end

  def generate_otp
    update_attributes(room_otp: SecureRandom.alphanumeric(8))
  end

  def destroy_otp
    update_attributes(room_otp: nil)
  end

  def nullify_co_hosts
    co_hosts.each do |host|
      host.update_attribute(:manager_id, nil)
    end
  end

  def plan_id
    subscribe_plan.id
  rescue
    nil
  end

  def update_plan(plan_id)
    subscription = self.subscription || Subscription.new(user: self)
    subscription.active = plan_id.present?
    subscription.plan_id = plan_id.present? ? plan_id : nil
    subscription.subscription_id = manual_subscription_id(subscription)
    subscription.paid = plan_id.present? ? 'paid' : 'unpaid'
    subscription.quantity = no_of_licenses
    subscription.skip_callbacks = true
    subscription.save
  end

  def auth_business
    return email.split('@').last unless default_mails.include?(email)
    nil
  end

  private

  #Create a monthly sessions if doesnt exist.

  def create_monthly_session(user)
    today = DateTime.now
    year = today.year
    month = today.month
    current_monthly_session = MonthlySession.new(:month => month, :year => year)
    current_monthly_session.user = user
    current_monthly_session.available_sessions = ENV['COMMUNITY_MONTHLY_SESSION_LIMIT']
    current_monthly_session.save!
    return current_monthly_session
  end

  # Destory a users rooms when they are removed.
  def destroy_rooms
    rooms.destroy_all
  end

  # Destory a users appointments when they are removed.
  def destroy_appointments
    appointments.destroy_all
  end

  def setup_user
    # Initializes a room for the user and assign a BigBlueButton user id.
    id = "gl-#{(0...12).map { rand(65..90).chr }.join.downcase }"

    update_attributes(uid: id)

    # Initialize the user to use the default user role
    role_provider = Rails.configuration.loadbalanced_configuration ? provider : "greenlight"

    Role.create_default_roles(role_provider) if Role.where(provider: role_provider).count.zero?

    # init user_profile
    UserProfile.create(name: full_name, user: self)
    Availability.create(user: self)
  end

  def check_if_email_can_be_blank
    if email.blank?
      if Rails.configuration.loadbalanced_configuration && greenlight_account?
        errors.add(:email, I18n.t("errors.messages.blank"))
      elsif provider == "greenlight"
        errors.add(:email, I18n.t("errors.messages.blank"))
      end
    end
  end

  def role_provider
    Rails.configuration.loadbalanced_configuration ? provider : "greenlight"
  end

  def manual_subscription_id(sub)
    return sub.subscription_id if sub.subscription_id&.include?('manual-sub')
    "manual_sub_#{(0...15).map { rand(65..90).chr }.join.downcase}"
  end

  def default_mails
    %w[@gmail @live @outlook @yahoo @hotmail @ymail @zoho @icloud]
  end

  def default_user_branding
    branding_hash = JSON.parse(theme_colors)
    branding_hash['primary_color'] = "#178BF7"
    branding_hash['primary_color_lighten'] = "#CCDCF8"
    branding_hash['primary_color_darken'] = "#1763F6"
    branding_hash['primary_color_background'] = "#F0F5FE"
    branding_hash['primary_color_text'] = "#178BF7"
    branding_hash.to_json
  end

  def set_default_branding
    self.theme_colors = default_user_branding
  end
end
