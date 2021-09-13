require 'google/api_client/client_secrets.rb'
require 'google/apis/calendar_v3'
require 'google/apis/people_v1'
class AppointmentsController < ApplicationController
  include AuthResource
  before_action :set_appointment, only: [:edit, :destroy, :update]
  before_action :set_host, only: [:create, :update, :destroy]

  def index
    @appointments = Appointment.get_appointments(current_user)
    @google_events_list = []
    if query_params[:appointment_date].present?
      @query_date = Date.parse(query_params[:appointment_date])
      @google_events_list = current_user.provider == "google" && current_user.integrated_google_calendar ? get_calendar_events(@query_date) : []
      @appointments = @appointments.where("start_date >= ? AND start_date <= ?", @query_date.beginning_of_day, @query_date.end_of_day).reorder('start_date ASC')
    end
  end

  def get_calendar_events(query_date)
    #Google calander events
    #
    token = current_user.google_calendar_token
    # Initialize Google Calendar API
    service = Google::Apis::CalendarV3::CalendarService.new
    # Use google keys to authorize
    service.authorization = token.google_secret.to_authorization
    # Request for a new access token just incase it expired
    if token.expired?
      new_access_token = service.authorization.refresh!
      token.access_token = new_access_token['access_token']
      token.expires_at =
          Time.now.to_i + new_access_token['expires_in'].to_i
      token.save
      # Authorise service with new access_token
      service.authorization = token.google_secret.to_authorization
    end
    # Get a list of calendars
    calendar_list = service.list_calendar_lists.items[0]
    @events_list = service.list_events(calendar_list.id, time_min: query_date.beginning_of_day.in_time_zone(current_user.timezone).to_datetime.rfc3339, time_max: query_date.end_of_day.in_time_zone(current_user.timezone).to_datetime.rfc3339).items
  end

  def new
    @appointment = current_user.appointments.new(timezone: current_user.timezone)
    @formatted_offset = Time.now.in_time_zone(@appointment.timezone).formatted_offset
  end

  def create
    @appointment = current_user.appointments.new(normalize_params)
    if check_valid_appointment && @appointment.save
      flash[:success] = I18n.t("appointment.create.success")
      respond_to do |format|
        format.html { redirect_to home_page }
        format.json { render body: @appointment.as_json(include: :participants) }
      end
    else
      respond_to do |format|
        format.html { render :new }
        format.json { render body: nil, status: 500 }
      end
    end
  end

  def update
    @appointment.assign_attributes(normalize_params)
    if check_valid_appointment && @appointment.save
      flash[:success] = I18n.t("appointment.update.success")
      respond_to do |format|
        format.html { redirect_to home_page }
        format.json { render body: @appointment.as_json(include: :participants) }
      end
    else
      respond_to do |format|
        format.html { render :edit }
        format.json { render body: nil, status: 500 }
      end
    end
  end

  def edit
    @formatted_offset = Time.now.in_time_zone(@appointment.timezone).formatted_offset
  end

  def destroy
    @appointment.destroy!
    flash[:success] = I18n.t("appointment.delete.success")
    respond_to do |format|
      format.js
      format.json { render body: nil, status: :no_content }
    end
  rescue => e
    flash[:alert] = I18n.t("appointment.delete.error", error: e)
    respond_to do |format|
      format.js
      format.json { render body: nil, status: 500 }
    end
  end

  private
  def set_appointment
    @appointment ||= current_user.appointments.find(params[:id])
  end

  def appointment_params
    params.require(:appointment).permit(
      :name,
      :start_date,
      :end_date,
      :timezone,
      :recurring,
      :recurring_type,
      :recurring_end_type,
      :recurring_meetings,
      :recurring_end_date,
      recurring_days: [],
      participants_attributes: [
        :id,
        :email,
        :_destroy
      ]
    )
  end

  def query_params
    params.require(:appointment).permit(
      :appointment_date
    )
  end

  def normalize_params
    offset = Time.now.in_time_zone(appointment_params[:timezone]).formatted_offset.to_s.gsub(':', '')
    appointment_params.merge(
      start_date: appointment_params[:start_date] + " " + params[:appointment][:start_time] + " " + offset,
      end_date: appointment_params[:start_date] + " " + params[:appointment][:end_time] + " " + offset
    )
  end

  def set_host
    Appointment.host ||= request.host_with_port
    Appointment.settings ||= @settings
  end

  def set_time_zone(&block)
    set_appointment if params[:id].present?
    timezone = @appointment.present? ? @appointment.timezone : current_user.timezone
    Time.use_zone(timezone, &block)
  end

  def check_valid_appointment
    @appointment.valid?
  end
end
