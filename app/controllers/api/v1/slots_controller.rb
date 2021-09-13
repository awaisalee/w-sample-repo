class Api::V1::SlotsController < Api::ApiController
  before_action :find_slot, only: [:show, :update, :destroy]

  def index
    render json: current_user.availability.slots, status: 200
  end

  def show
    render json: @slot, status: 200
  end

  def create
    @slot = current_user.availability.slots.new(slot_params)
    if @slot.save
      render json: @slot, status: 200
    else
      render json: { error: @slot.errors.full_messages.join }, status: 403
    end
  end

  def update
    if @slot.update(slot_params)
      render json: @slot, status: 200
    else
      render json: { error: @slot.errors.full_messages.join }, status: 403
    end
  end

  def destroy
    if @slot.destroy
      render json: {}, status: 204
    else
      render json: { error: @slot.errors.full_messages.join }, status: 403
    end
  end

  private

  def find_slot
    @slot = current_user.availability.slots.find_by(id: params[:id])
  end

  def slot_params
    params.require(:slot).permit(
      :day,
      :start_time,
      :end_time,
      :state
    )
  end

end
