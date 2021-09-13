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

module Emailer
  extend ActiveSupport::Concern
  include Rails.application.routes.url_helpers
  include Calendar

  included do
    cattr_accessor :host
    cattr_accessor :settings
  end

  # Sends account activation email.
  def send_activation_email(user, token)
    begin
      return unless Rails.configuration.enable_email_verification

      UserMailer.verify_email(user, user_verification_link(token), @settings).deliver
    rescue => e
      logger.error "Support: Error in email delivery: #{e}"
      flash[:alert] = I18n.t(params[:message], default: I18n.t("delivery_error"))
    else
      flash[:success] = I18n.t("email_sent", email_type: t("verify.verification"))
    end
  end

  # Sends password reset email.
  def send_password_reset_email(user, token, source='app')
    begin
      return unless Rails.configuration.enable_email_verification
      UserMailer.password_reset(user, reset_link(token, source), @settings).deliver_now
    rescue => e
      logger.error "Support: Error in email delivery: #{e}"
      flash[:alert] = I18n.t(params[:message], default: I18n.t("delivery_error"))
    else
      flash[:success] = I18n.t("email_sent", email_type: t("reset_password.subtitle"))
    end
  end

  # Sends password changed email.
  def send_password_changed_email(user, token)
    begin
      return unless Rails.configuration.enable_email_verification

      UserMailer.password_changed(user, reset_link(token), @settings).deliver_now
    rescue => e
      logger.error "Support: Error in email delivery: #{e}"
      flash[:alert] = I18n.t(params[:message], default: I18n.t("delivery_error"))
    else
      flash[:success] = I18n.t("email_sent", email_type: t("changed_password.subtitle"))
    end
  end

  def send_user_promoted_email(user, role)
    begin
      return unless Rails.configuration.enable_email_verification

      UserMailer.user_promoted(user, role, root_url, @settings).deliver_now
    rescue => e
      logger.error "Support: Error in email delivery: #{e}"
      flash[:alert] = I18n.t(params[:message], default: I18n.t("delivery_error"))
    end
  end

  def send_user_demoted_email(user, role)
    begin
      return unless Rails.configuration.enable_email_verification

      UserMailer.user_demoted(user, role, root_url, @settings).deliver_now
    rescue => e
      logger.error "Support: Error in email delivery: #{e}"
      flash[:alert] = I18n.t(params[:message], default: I18n.t("delivery_error"))
    end
  end

  # Sends inivitation to join
  def send_invitation_email(name, email, token)
    begin
      return unless Rails.configuration.enable_email_verification

      UserMailer.invite_email(name, email, invitation_link(token), @settings).deliver_now
    rescue => e
      logger.error "Support: Error in email delivery: #{e}"
      flash[:alert] = I18n.t(params[:message], default: I18n.t("delivery_error"))
    else
      flash[:success] = I18n.t("administrator.flash.invite", email: email)
    end
  end

  def send_user_approved_email(user)
    begin
      return unless Rails.configuration.enable_email_verification

      UserMailer.approve_user(user, root_url, @settings).deliver_now
    rescue => e
      logger.error "Support: Error in email delivery: #{e}"
      flash[:alert] = I18n.t(params[:message], default: I18n.t("delivery_error"))
    else
      flash[:success] = I18n.t("email_sent", email_type: t("verify.verification"))
    end
  end

  def send_approval_user_signup_email(user)
    begin
      return unless Rails.configuration.enable_email_verification
      admin_emails = admin_emails()
      UserMailer.approval_user_signup(user, admins_url(tab: "pending"),
      admin_emails, @settings).deliver_now unless admin_emails.empty?
    rescue => e
      logger.error "Support: Error in email delivery: #{e}"
      flash[:alert] = I18n.t(params[:message], default: I18n.t("delivery_error"))
    end
  end

  def send_invite_user_signup_email(user)
    begin
      return unless Rails.configuration.enable_email_verification

      admin_emails = admin_emails()
      UserMailer.invite_user_signup(user, admins_url, admin_emails, @settings).deliver_now unless admin_emails.empty?
    rescue => e
      logger.error "Support: Error in email delivery: #{e}"
      flash[:alert] = I18n.t(params[:message], default: I18n.t("delivery_error"))
    end
  end

  def send_contact_feedback_email(user, contact)
    begin
      ContactMailer.contact_feedback(user, contact, @settings).deliver_now
    rescue => e
      logger.error "Support: Error in email delivery: #{e}"
      flash[:alert] = I18n.t(params[:message], default: I18n.t("delivery_error"))
    end
  end

  def send_meeting_invitation_email(appointment, attendee, action)
    begin
      room_link = get_room_link(room, appointment)
      room_code = room.access_code
      calendar_data = get_ical(appointment, user, attendee, room_link, room_code)
      room_settings = JSON.parse(room.room_settings)
      registered = room_settings['authMandatory'] ? RegisteredEmail.where(email: attendee.email).any? ? nil : registeration_link : nil
      attendee_user = User.find_by(email: attendee.email) || {email: attendee.email}
      timezone = attendee_user.try(:timezone) || appointment.timezone
      UserMailer.meeting_invitation(user, appointment, room_code, room_link, attendee_user, calendar_data, timezone, action, settings, registered).deliver_later
    rescue => e
      logger.error "Support: Error in email delivery: #{e}"
      flash[:alert] = I18n.t(params[:message], default: I18n.t("delivery_error"))
    end
  end

  def send_meeting_dropped_email(appointment, attendee)
    begin
      room_link = get_room_link(room, appointment)
      room_code = room.access_code
      calendar_data = get_ical(appointment, user, attendee, room_link, room_code, 'drop')
      attendee_user = User.find_by(email: attendee.email) || {email: attendee.email}
      timezone = attendee_user.try(:timezone) || appointment.timezone
      UserMailer.meeting_dropped(user, appointment, attendee_user, settings, room&.access_code, timezone, calendar_data).deliver_later
    rescue => e
      logger.error "Support: Error in email delivery: #{e}"
      flash[:alert] = I18n.t(params[:message], default: I18n.t("delivery_error"))
    end
  end

  def send_user_room_otp(user, room)
    begin
      UserMailer.user_room_otp(user, room, @settings).deliver_now
    rescue => e
      logger.error "Support: Error in email delivery: #{e}"
      flash[:alert] = I18n.t(params[:message], default: I18n.t("delivery_error"))
    end
  end

  def send_account_deactivate_email(user, url)
    begin
      UserMailer.account_deactivate(user, @settings, url).deliver_now
    rescue => e
      logger.error "Support: Error in email delivery: #{e}"
      flash[:alert] = I18n.t(params[:message], default: I18n.t("delivery_error"))
    end
  end

  def send_susbcription_cancel_email(user)
    begin
      UserMailer.cancel_subscription(user, @settings).deliver_now
    rescue => e
      logger.error "Support: Error in email delivery: #{e}"
      flash[:alert] = I18n.t(params[:message], default: I18n.t("delivery_error"))
    end
  end

  def send_signup_invitation_email(from_user, email, token)
    begin
      UserMailer.signup_invitation(from_user, email, signup_invite_link(token), @settings).deliver_now
      UserMailer.cohost_invitation_to_admin(from_user, email, @settings).deliver_now
    rescue => e
      logger.error "Support: Error in email delivery: #{e}"
      flash[:alert] = I18n.t(params[:message], default: I18n.t("delivery_error"))
    end
  end

  def send_co_host_invitation_email(from_user, to_user)
    begin
      UserMailer.co_host_invitation(from_user, to_user, signin_url, @settings).deliver_now
      UserMailer.cohost_invitation_to_admin(from_user, to_user.email, @settings).deliver_later
    rescue => e
      logger.error "Support: Error in email delivery: #{e}"
      flash[:alert] = I18n.t(params[:message], default: I18n.t("delivery_error"))
    end
  end

  def send_drop_cohost_email(from_user, to_user)
    begin
      UserMailer.drop_cohost(from_user, to_user, @settings).deliver_later
      UserMailer.drop_cohost(from_user, to_user, @settings, to_admin: true).deliver_later
    rescue => e
      logger.error "Support: Error in email delivery: #{e}"
      flash[:alert] = I18n.t(params[:message], default: I18n.t("delivery_error"))
    end
  end

  # Sends answer reset email.
  def send_answer_reset_email(user, token)
    begin
      UserMailer.answer_reset(user, reset_answers_set_answer_url(id: token), @settings).deliver_now
    rescue => e
      logger.error "Support: Error in email delivery: #{e}"
      flash[:alert] = I18n.t(params[:message], default: I18n.t("delivery_error"))
    end
  end

  def send_sessions_left_reminder_email(user)
    begin
      UserMailer.sessions_left_reminder_email(user).deliver_later
    rescue => e
      logger.error "Support: Error in email delivery: #{e}"
      flash[:alert] = I18n.t(params[:message], default: I18n.t("delivery_error"))
    end
  end

  def send_upgrade_account_email(user)
    begin
      UserMailer.upgrade_account_email(user).deliver_later
    rescue => e
      logger.error "Support: Error in email delivery: #{e}"
      flash[:alert] = I18n.t(params[:message], default: I18n.t("delivery_error"))
    end
  end

  def send_first_session_feedback_email(user)
    begin
      UserMailer.first_session_feedback_email(user).deliver_later
    rescue => e
      logger.error "Support: Error in email delivery: #{e}"
      flash[:alert] = I18n.t(params[:message], default: I18n.t("delivery_error"))
    end
  end

  def send_whistle_plus_welcome_email(user)
    begin
      UserMailer.whistle_plus_welcome(user).deliver_later
    rescue => e
      logger.error "Support: Error in email delivery: #{e}"
      flash[:alert] = I18n.t(params[:message], default: I18n.t("delivery_error"))
    end
  end

  def send_whistle_pro_welcome_email(user)
    begin
      UserMailer.whistle_pro_welcome(user).deliver_later
    rescue => e
      logger.error "Support: Error in email delivery: #{e}"
      flash[:alert] = I18n.t(params[:message], default: I18n.t("delivery_error"))
    end
  end

  def send_whistle_plus_trial_reminder_email(user)
    begin
      UserMailer.whistle_plus_trial_reminder(user).deliver_later
    rescue => e
      logger.error "Support: Error in email delivery: #{e}"
      flash[:alert] = I18n.t(params[:message], default: I18n.t("delivery_error"))
    end
  end

  private

  # Returns the link the user needs to click to verify their account
  def user_verification_link(token)
    edit_account_activation_url(token: token)
  end

  def admin_emails
    roles = Role.where(provider: @user_domain, role_permissions: { name: "can_manage_users", value: "true" })
                .pluck(:name)

    admins = User.with_role(roles - ["super_admin"])

    admins = admins.where(provider: @user_domain) if Rails.configuration.loadbalanced_configuration

    admins.collect(&:email).join(",")
  end

  def reset_link(token, source='app')
    if source === 'api'
      "#{ENV['WHISTLE_LIVE_HOST']}/reset-password/#{token}"
    else
      edit_password_reset_url(token)
    end
  end

  def invitation_link(token)
    if allow_greenlight_accounts?
      signup_url(invite_token: token)
    else
      root_url(invite_token: token)
    end
  end

  def get_room_link(room, appointment)
    relative_path = Rails.configuration.relative_url_root.sub('/', '').concat('/') rescue '/'
    _params = { session_event: appointment.id }
    _params[:pwd] = BCrypt::Password.create(room.access_code) if room.access_code.present?
    URI.join(root_url(host: host), relative_path, room_path(room, _params).sub('/', '')).to_s
  end

  def registeration_link
    relative_path = Rails.configuration.relative_url_root.sub('/', '').concat('/') rescue '/'
    URI.join(root_url(host: host), relative_path, signup_path.sub('/', '')).to_s
  end

  def signup_invite_link(token)
    signup_url(invite_token: token)
  end
end
