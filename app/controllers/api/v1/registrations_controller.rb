class Api::V1::RegistrationsController < Api::ApiController
  include Registrar
  include Emailer
  skip_before_action :auth0_authenticate_request!

  def create
    @user = User.include_deleted.find_or_initialize_by(email: user_params[:email])

    user_previously_deleted = @user.deleted?
    if user_previously_deleted || !@user.persisted? || params[:invite_token].present?
      @user.assign_attributes(user_params)
      @user.provider = @user_domain
      @user.assign_attributes(default_recovered_params) if user_previously_deleted
      @user.assign_attributes(no_of_licenses: 1, business_role: nil) if @user.personal?
      @user.business_name = @user.auth_business unless @user.business_name.present?

      # Redirect to root if user token is either invalid or expired
      return render json: { error: I18n.t("registration.invite.fail") }, status: 500 unless passes_invite_reqs

      # User has passed all validations required
      @user.save

      # for invited user only
      if params[:invite_token].present?
        # activate invited user
        @user.activate
        return login_user
      end

      # Set user to pending and redirect if Approval Registration is set
      if approval_registration && !@user.activated?
        @user.set_role :pending
        return render json: { success: I18n.t("registration.approval.signup") }, status: 200 unless Rails.configuration.enable_email_verification
      end

      send_registration_email

      # Sign in automatically if email verification is disabled or if user is already verified.
      if !Rails.configuration.enable_email_verification || @user.email_verified
        @user.set_role :user unless @user.rollified?
        return login_user
      end

      send_activation_email(@user, @user.create_activation_token)
      VerifyEmailReminderJob.set(wait: 24.hours).perform_later(@user.id)
      @price_id = params[:user][:price_id]
      @quantity = params[:user][:no_of_licenses]

      if @price_id.present? and @quantity.present?
        # set user role and make a default room
        @user.set_role :user unless @user.rollified?
        # login the user and by-pass email verification
        return login_user
      end
    else
      return render json: { error: "Email " + I18n.t("errors.messages.taken") }, status: 403
    end
    return render json: { success: I18n.t("registration.success") }, status: 200
  end

  private

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

  def default_recovered_params
    {
      deleted: false,
      email_verified: false,
      role_id: nil,
      activation_digest: nil,
      activated_at: nil
    }
  end

  def login_user
    command = AuthenticateUser.call(user_params[:email], user_params[:password])
    if command.success?
      render json: { auth_token: command.result }
    else
      render json: { error: command.errors }, status: :unauthorized
    end
  end
end
