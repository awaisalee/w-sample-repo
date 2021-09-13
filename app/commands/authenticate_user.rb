# app/commands/authenticate_user.rb

class AuthenticateUser
  prepend SimpleCommand

  def initialize(email, password)
    @email = email
    @password = password
  end

  def call
    JsonWebToken.encode(user_id: user.id) if user
  end

  private
  attr_accessor :email, :password

  def user
    user = User.include_deleted.find_by(email: email.try(:downcase))
    is_super_admin = user&.has_role? :super_admin

    # Check user with that email exists
    unless user
      errors.add :user_authentication, I18n.t("invalid_credentials")
      return nil
    end

    # Check that the user is a Greenlight account
    unless user.greenlight_account?
      errors.add :user_authentication, I18n.t("invalid_login_method", omniauth: user.try(:provider))
      return nil
    end

    # Check correct password was entered
    unless user.try(:authenticate, password)
      errors.add :user_authentication, I18n.t("invalid_credentials")
      return nil
    end

    # Check that the user is not deleted
    if user.deleted?
      errors.add :user_authentication, I18n.t("registration.banned.fail")
      return nil
    end

    unless is_super_admin
      # Check that the user has verified their account
      unless user.activated?
        errors.add :user_authentication, I18n.t("registration.approval.fail")
        return nil
      end
    end

    return user

  rescue BCrypt::Errors::InvalidHash
    errors.add :user_authentication, I18n.t("invalid_credentials")
    return nil
  end
end
