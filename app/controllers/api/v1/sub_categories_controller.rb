class Api::V1::SubCategoriesController < Api::ApiController
  before_action :find_category, only: [:update, :show, :destroy]
  skip_before_action :auth0_authenticate_request!, only: [:index, :show]

  def index
    render json: SubCategory.all, status: 200
  end

  def create
    @sub_category = SubCategory.new(category_params)
    if @sub_category.save
      render json: @sub_category, status: 201
    else
      render json: { error: @sub_category.errors.full_messages.join }, status: 403
    end
  end

  def update
    if @sub_category.update(category_params)
      render json: @sub_category, status: 200
    else
      render json: { error: @sub_category.errors.full_messages.join }, status: 403
    end
  end

  def show
    render json: @sub_category, status: 200
  end

  def destroy
    if @sub_category.destroy
      render json: { }, status: 204
    else
      render json: { error: @sub_category.errors.full_messages.join }, status: 403
    end
  end

  private

  def find_category
    @sub_category = SubCategory.find_by(id: params[:id])
    return render json: { error: "Category not found" }, status: 404 unless @sub_category
  end

  def category_params
    params.require(:category).permit(
      :title,
      :description,
      :category_id,
      :is_active
    )
  end
end
