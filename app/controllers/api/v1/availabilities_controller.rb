class Api::V1::AvailabilitiesController < Api::ApiController
  before_action :find_availability

  def show
    render json: @availability, status: 200
  end

  def update
    if @availability.update(availability_params)
      render json: @availability, status: 200
    else
      render json: { error: @availability.errors.full_messages.join }, status: 403
    end
  end

  private

  def find_availability
    @availability = if params[:id] == "me"
                      current_user.availability
                    else
                      Availability.find_by_id(params[:id])
                    end
  end

  def availability_params
    params.require(:availability).permit(
      :user_id,
      :book_from_profile,
      :collect_payment,
      :session_length,
      :price,
      :timezone,
      slots_attributes: [
        :id,
        :_destroy,
        :day,
        :start_time,
        :end_time,
        :state
      ]
    )
  end
end
