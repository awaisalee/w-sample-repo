class Api::V1::CategoriesController < Api::ApiController
  before_action :find_category, only: [:update, :show, :destroy]
  skip_before_action :auth0_authenticate_request!, only: [:index, :show]

  def index
    render json: Category.all, status: 200
  end

  def create
    @category = Category.new(category_params)
    if @category.save
      render json: @category, status: 201
    else
      render json: { error: @category.errors.full_messages.join }, status: 403
    end
  end

  def update
    if @category.update(category_params)
      render json: @category, status: 200
    else
      render json: { error: @category.errors.full_messages.join }, status: 403
    end
  end

  def show
    render json: @category, status: 200
  end

  def destroy
    if @category.destroy
      render json: { }, status: 204
    else
      render json: { error: @category.errors.full_messages.join }, status: 403
    end
  end

  private

  def find_category
    @category = Category.find_by(id: params[:id])
    return render json: { error: "Category not found" }, status: 404 unless @category
  end

  def category_params
    params.require(:category).permit(
      :title,
      :description,
      :category_id
    )
  end
end
