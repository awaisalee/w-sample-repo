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

class UsersController < ApplicationController
  include Pagy::Backend
  include Authenticator
  include Emailer
  include Registrar
  include Recorder
  include Rolify

  before_action :find_user, only: [:edit, :change_password, :delete_account, :update, :update_password, :subscription_account, :remove_as_host, :manage_team, :validate_username]
  before_action :check_for_manager, only: [:manage_team]
  before_action :ensure_unauthenticated_except_twitter, only: [:create]
  before_action :check_user_signup_allowed, only: [:create]
  before_action :check_admin_of, only: [:edit, :change_password, :delete_account, :subscription_account]

  # POST /u
  def create
    @user = User.include_deleted.find_or_initialize_by(email: user_params[:email])
    user_previously_deleted = @user.deleted?

    if user_previously_deleted || !@user.persisted? || params[:invite_token].present?
      @user.assign_attributes(user_params)
      @user.provider = @user_domain
      @user.assign_attributes(default_recovered_params) if user_previously_deleted
      @user.assign_attributes(no_of_licenses: 1, business_role: nil) if @user.personal?
      @user.business_name = @user.auth_business unless @user.business_name.present?

      # User or recpatcha is not valid
      unless valid_user_or_captcha
        respond_to do |format|
          format.html { render("sessions/new") }
          format.js
        end
        return
      end

      # Redirect to root if user token is either invalid or expired
      return redirect_to root_path, flash: { alert: I18n.t("registration.invite.fail") } unless passes_invite_reqs

      # User has passed all validations required
      @user.save

      logger.info "Support: #{@user.email} user has been created."

      # for invited user only
      if params[:invite_token].present?
        # activate invited user
        @user.activate
        login(@user) && return
      end

      # Set user to pending and redirect if Approval Registration is set
      if approval_registration && !@user.activated?
        @user.set_role :pending

        return redirect_to root_path,
                           flash: { success: I18n.t("registration.approval.signup") } unless Rails.configuration.enable_email_verification
      end

      send_registration_email

      # Sign in automatically if email verification is disabled or if user is already verified.
      if !Rails.configuration.enable_email_verification || @user.email_verified
        @user.set_role :user unless @user.rollified?
        login(@user) && return
      end

      send_activation_email(@user, @user.create_activation_token)
      VerifyEmailReminderJob.set(wait: 24.hours).perform_later(@user.id)
      @price_id = params[:user][:price_id]
      @quantity = params[:user][:no_of_licenses]

      if @price_id.present? and @quantity.present?
        # set user role and make a default room
        @user.set_role :user unless @user.rollified?
        # login the user and by-pass email verification
        login(@user, back: true)

        respond_to { |format| format.js }
        return
      end
    else
      redirect_to root_path, flash: { alert: "Email " +I18n.t("errors.messages.taken") }
      return
    end

    redirect_to root_path
  end

  # GET /u/:user_uid/edit
  def edit
    redirect_to root_path unless current_user
  end

  # GET /u/:user_uid/change_password
  def change_password
    redirect_to edit_user_path unless current_user.greenlight_account?
  end

  # GET /u/:user_uid/delete_account
  def delete_account
  end

  # GET /u/:user_uid/subscription_account
  def subscription_account
  end

  # GET /u/:user_uid/manage_team
  def manage_team
  end

  # GET /u/:user_uid/validate_username
  def validate_username
    render json: { valid: !(Room.where.not(id: @user.main_room.id).exists?(uid: params[:room_uid])) }
  end

  # POST /u/:user_uid/edit
  def update
    if session[:prev_url].present?
      path = session[:prev_url]
      session.delete(:prev_url)
    else
      path = admins_path
    end

    redirect_path = current_user.admin_of?(@user, "can_manage_users") ? path : edit_user_path(@user)

    unless @user.greenlight_account?
      # Allow all users to update info for now
      # params[:user][:first_name] = @user.first_name
      # params[:user][:last_name] = @user.last_name
      params[:user][:email] = @user.email
    end


    if params[:user][:room_uid].present? && @user.main_room.present? && @user.subscribed?
      @user.main_room.update_attributes(uid: params[:user][:room_uid].downcase) if params[:user][:room_uid].downcase != @user.main_room.uid
    end
    if params[:theme_colors].present?
      params[:user][:theme_colors] = ActiveSupport::JSON.encode(params[:theme_colors])
    end

    if @user.update_attributes(user_params)
      if user_params.has_key? :email and user_params[:email].downcase != @user.email
        @user.update_attributes(email_verified: false)
        send_activation_email(@user, @user.create_activation_token)
      end

      user_locale(@user)

      if params[:user].has_key? :plan_id
        @user.update_plan(params[:user][:plan_id])
      end

      if is_production? && @user.business?
        Analytics.group(
          user_id: @user.id,
          group_id: @user.business_name_to_group_id,
          traits: {
            name: @user.sub_business
          })
      end

      if update_roles(params[:user][:role_id])
        return redirect_to redirect_path, flash: { success: I18n.t("info_update_success") }
      else
        flash[:alert] = I18n.t("administrator.roles.invalid_assignment")
      end
    end

    Analytics.identify(
      user_id: user.id,
      traits: {
        first_name: @user.first_name,
        last_name: @user.first_name,
        email: @user.email,
        available_sessions: @user.remaining_monthly_sessions,
        host: @user.manager? ? "Co Host" : "Host",
        plan: @user.plan_name.humanize,
        plan_duration: @user.subscribe_plan&.interval.nil? ? 0 : user.subscribe_plan&.interval,
        account_type: @user.account_type,
        account_creation_date: @user.created_at,
        org_role: @user.business_role,
        number_of_licenses: @user.no_of_licenses
      })

    render :edit
  end

  # POST /u/:user_uid/change_password
  def update_password
    # Update the users password.
    if @user.authenticate(user_params[:password])
      # Verify that the new passwords match.
      if user_params[:new_password] == user_params[:password_confirmation]
        @user.password = user_params[:new_password]
      else
        # New passwords don't match.
        @user.errors.add(:password_confirmation, "doesn't match")
      end
    else
      # Original password is incorrect, can't update.
      @user.errors.add(:password, "is incorrect")
    end

    # Notify the user that their account has been updated.
    if @user.errors.empty? && @user.save
      send_password_changed_email(@user, @user.create_reset_digest)
      return redirect_to change_password_path, flash: { success: I18n.t("info_update_success") }
    end

    # redirect_to change_password_path
    render :change_password
  end

  # DELETE /u/:user_uid
  def destroy
    # Include deleted users in the check
    admin_path = request.referer.present? ? request.referer : admins_path
    @user = User.include_deleted.find_by(uid: params[:user_uid])

    logger.info "Support: #{current_user.email} is deleting #{@user.email}."

    self_delete = current_user == @user
    redirect_url = self_delete ? root_path : admin_path

    begin
      if current_user && (self_delete || current_user.admin_of?(@user, "can_manage_users"))
        # Permanently delete if the user is deleting themself
        perm_delete = self_delete || (params[:permanent].present? && params[:permanent] == "true")

        # Permanently delete the rooms under the user if they have not been reassigned
        if perm_delete
          @user.rooms.include_deleted.each do |room|
            room.destroy(false)
          end
        end

        # Soft delete it for now bcs we are using room details in mailing
        @user.destroy(false)

        # Log the user out if they are deleting themself
        session.delete(:user_id) if self_delete
        cookies.delete(:auth_token)

        # send deactivate account email to user
        send_account_deactivate_email(@user, contact_url)

        return redirect_to redirect_url, flash: { success: I18n.t("administrator.flash.delete") } unless self_delete
      else
        flash[:alert] = I18n.t("administrator.flash.delete_fail")
      end
    rescue => e
      logger.error "Support: Error in user deletion: #{e}"
      flash[:alert] = I18n.t(params[:message], default: I18n.t("administrator.flash.delete_fail"))
    end

    redirect_to redirect_url
  end

  # GET /u/:user_uid/recordings
  def recordings
    if current_user && current_user.uid == params[:user_uid]
      @search, @order_column, @order_direction, recs =
        all_recordings(current_user.rooms.pluck(:bbb_id), params.permit(:search, :column, :direction), true)
      @pagy, @recordings = pagy_array(recs)
    else
      redirect_to root_path
    end
  end

  # GET | POST /terms
  def terms
    redirect_to '/404' unless Rails.configuration.terms

    if params[:accept] == "true"
      current_user.update_attributes(accepted_terms: true)
      login(current_user)
    end
  end

  # co-hosts management
  def edit_co_hosts
    @user = User.find_by(id: params[:user_id]) || current_user
    @co_hosts = @user.co_hosts
  end

  def update_co_hosts
    emails = params[:emails].split(',').map(&:downcase).uniq.reject(&:blank?) if params[:emails].present?
    manager = User.find_by(uid: params[:user_uid]) || current_user
    present_cohost_ids = manager.co_hosts.ids
    left_users = User.where(email: emails).where.not(email: manager.email).where.not(id: present_cohost_ids)

    # remove co-hosts
    if manager.co_hosts.any?
      manager.co_hosts.where.not(id: left_users.ids).each do |user|
        user.assign_attributes(manager_id: nil)
        user.save(validate: false)
        send_drop_cohost_email(manager, user)
      end
    end

    left_emails = emails - left_users.map(&:email) rescue []

    if left_emails.any?
      left_emails.each do |email|
        invited_user = User.find_or_initialize_by(email: email)
        invited_user.assign_attributes(manager_id: manager.id, account_type: :business, business_name: manager.business_name)
        invited_user.save(validate: false)

        send_signup_invitation_email(manager, email, invited_user.create_activation_token)
      end
    end

    if left_users.any?
      left_users.each do |user|
        user.assign_attributes(manager_id: manager.id, account_type: :business, business_name: manager.business_name)
        user.save(validate: false)
        send_co_host_invitation_email(manager, user)
      end

      left_users.each do |u|
        if is_production?
          # TODO : Add first_name and last_name later once users update their details in profile
          Analytics.identify(
            user_id: u.id,
            traits: {
              email: u.email,
              available_sessions: 0,
              host: "Co Host",
              account_type: "Business",
              account_creation_date: u.created_at
            }
          )
        end
      end
    end

    @co_hosts = manager.co_hosts.reload

    if manager.id == current_user.id
      redirect_to manage_team_path(current_user)
    else
      redirect_to admin_edit_user_path(user_uid: manager.uid)
    end
  end

  def remove_as_host
    @manager = User.find_by(uid: params[:manager_uid]) || current_user
    @user.assign_attributes(manager_id: nil, business_name: @user.auth_business, account_type: :personal)
    @user.save(validate: false)
    send_drop_cohost_email(@manager, @user)
  end

  def add_as_host
    invited_user = User.find_or_initialize_by(email: params[:email])
    manager = User.find_by(uid: params[:user_uid]) || current_user
    invited_user.assign_attributes(manager_id: manager.id, business_name: manager.business_name, account_type: :business)
    existing_user = invited_user.id?
    invited_user.save(validate: false)

    if existing_user
      send_co_host_invitation_email(manager, invited_user)
    else
      send_signup_invitation_email(manager, invited_user.email, invited_user.create_activation_token)
    end

    if manager.id == current_user.id
      redirect_to manage_team_path(current_user)
    else
      redirect_to admin_edit_user_path(user_uid: manager.uid)
    end
  end

  private

  def find_user
    @user = User.find_by(uid: params[:user_uid])
  end

  # Verify that GreenLight is configured to allow user signup.
  def check_user_signup_allowed
    redirect_to root_path unless Rails.configuration.allow_user_signup
  end

  def user_params
    params.require(:user).permit(
      :first_name,
      :last_name,
      :email,
      :timezone,
      :image,
      :brand_image,
      :password,
      :password_confirmation,
      :new_password,
      :accepted_terms,
      :account_type,
      :business_name,
      :business_role,
      :phone_number,
      :no_of_licenses,
      :brand_image_attachment,
      :theme_colors,
    )
  end

  def send_registration_email
    if invite_registration
      send_invite_user_signup_email(@user)
    elsif approval_registration
      send_approval_user_signup_email(@user)
    end
  end

  # Checks that the user is allowed to edit this user
  def check_admin_of
    redirect_to root_path if current_user &&
                             @user != current_user &&
                             !current_user.admin_of?(@user, "can_manage_users")
  end

  def check_for_manager
    redirect_to home_page unless current_user.manager?
  end

  def default_recovered_params
    {
      deleted: false,
      email_verified: false,
      role_id: nil,
      activation_digest: nil,
      activated_at: nil
    }
  end

  def update_banner
  end
end
