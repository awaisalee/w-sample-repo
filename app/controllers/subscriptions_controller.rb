class SubscriptionsController < ApplicationController
  include Emailer

  skip_before_action :verify_authenticity_token, only: [:checkout, :webhooks, :start_trial]
  before_action :verify_enable_pricing

  Stripe.api_key = ENV['STRIPE_PRIVATE_KEY']

  def update
    if params[:user_uid].present?
      user = User.find_by(uid: params[:user_uid])
    else
      user = current_user
    end
  
    return redirect_to home_page unless user.subscription.present?
    present = user.subscription.quantity
    post = params[:subscription][:quantity].to_i

    if user.id == current_user.id
      user.subscription.update(quantity: present + post)
      redirect_to manage_team_path(invite: true)
    else
      user.subscription.update(quantity: present + post, skip_callbacks: true)
      redirect_to admin_edit_user_path(user_uid: user.uid)
    end
  end

  def success
  end

  def checkout
    @plan = Plan.find_by(stripe_price_id: params[:price_id])
    @quantity = params[:quantity].to_i || 1

    # we should mark the user as business if he purchases more than 1 licenses
    # if params[:account_type].present?
    #   current_user.update_attribute('account_type', params[:account_type])
    # end

    session = Stripe::Checkout::Session.create(session_opts)
    render json: { id: session.id }.to_json
  end

  def webhooks
    endpoint_secret = ENV['STRIPE_SIGNING_SECRET']
    begin
      sig_header = request.env['HTTP_STRIPE_SIGNATURE']
      payload = request.body.read
      event = Stripe::Webhook.construct_event(payload, sig_header, endpoint_secret)

      case event['type']
      when 'checkout.session.completed'
        checkout_session = event['data']['object']
        subscription_id = checkout_session.subscription
        customer_email = checkout_session.customer_email
        customer_email = checkout_session.customer_details["email"] unless customer_email
        customer = User.find_by_email(customer_email)

        # Creating / Editing an existing subscription
        subscription = customer.subscription || Subscription.new
        subscription.active = true
        subscription.user = customer
        subscription.subscription_id = subscription_id
        subscription.paid = checkout_session.payment_status
        subscription.save!

        #send mail
        if subscription.plan.plan_type == "whistle_plus"
          send_whistle_plus_welcome_email(subscription.user) if ENV['HUBSPOT_EMAIL_ENABLED']
          td = TimeDifference.between(Time.now, subscription.trial_end).in_days - 5
          WhistlePlusTrialReminderJob.set(wait: "#{td.to_i} days").perform_later(subscription.user.id) if ENV['HUBSPOT_EMAIL_ENABLED']
        elsif subscription.plan.plan_type == "whistle_pro"
          send_whistle_pro_welcome_email(subscription.user) if ENV['HUBSPOT_EMAIL_ENABLED']
        end

        # TODO : Add first_name and last_name later once users update their details in profile
        if is_production?
          Analytics.identify(
            user_id: customer.id,
            traits: {
              email: customer.email,
              plan: customer.plan_name.humanize,
              plan_duration: customer.subscribe_plan&.interval.nil? ? 0 : @user.subscribe_plan&.interval,
              account_type: customer.account_type,
            }
          )
          segment_upgrade_date(customer.email)
        end
      when 'customer.subscription.deleted'
        subscription_id = event['data']['object']['id']
        subscription = Subscription.find_by(subscription_id: subscription_id)
        subscription.update(active: false) if subscription
      when 'invoice.paid'
        puts "invoice has been paid "
      when 'invoice.payment_failed'
        puts "invoice payment failed"
      end
    rescue JSON::ParserError => e
      return status 400
    rescue Stripe::SignatureVerificationError => e
      return status 400
    end
  end

  def cancel_subscription
    subscription_id = current_user.subscription.subscription_id
    Stripe::Subscription.update(
      subscription_id.to_s,
      {
        cancel_at_period_end: true,
      }
    ) if subscription_id.present?
    # cancel user subscriptions
    current_user.subscription.update(cancel_at: DateTime.now)
    send_susbcription_cancel_email(current_user)
    flash[:info] = "Your subscription has been cancelled by the end of current billing cycle"
  end

  def start_trial
    subscription = current_user.subscription || Subscription.new
    subscription.skip_callbacks = true
    subscription.active = true
    subscription.user = current_user
    subscription.subscription_id = nil
    subscription.paid = "paid"
    subscription.plan_id = Plan.find_by(stripe_price_id: params[:price_id]).id
    if subscription.cancel_at.present?
      difference = (subscription.trial_end.to_date - subscription.cancel_at.to_date).to_i
      subscription.trial_end = (Time.now + difference.days).to_datetime
      subscription.cancel_at = nil
    else
      subscription.trial_start = Time.now.to_datetime
      subscription.trial_end = (Time.now + 30.days).to_datetime
    end
    subscription.save
    render json: { path: root_path }.to_json
  end

  private
  def verify_enable_pricing
    redirect_to home_page unless enable_pricing?
  end

  def success_url
    if current_user.present?
      if @quantity > 1
        return manage_team_url(current_user, invite: true)
      else
        return room_url(current_user.main_room)
      end
    else
      return thank_you_url
    end
  end

  def session_opts
    opts = {
      payment_method_types: ['card'],
      line_items: [{
        price: params[:price_id],
        quantity: @quantity,
      }],
      mode: 'subscription',
      success_url: success_url,
      cancel_url: pricing_url,
    }

    if params[:additional_licenses].present?
      opts[:metadata] = {
        plan: current_user.try(:plan_name),
        total_licenses: current_user.subscription.quantity + @quantity,
        type: 'additional_licenses'
      }
    elsif @plan.whistle_plus?
      opts[:metadata] = {}
      opts[:subscription_data] = {}
    else
      opts[:metadata] = {}
    end

    if current_user.subscription&.customer_id
      opts[:customer] = current_user.subscription.customer_id
    else
      opts[:customer_email] = current_user.try(:email)
    end

    opts
  end
end
