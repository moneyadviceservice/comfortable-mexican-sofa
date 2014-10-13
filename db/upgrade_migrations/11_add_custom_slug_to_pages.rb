class AddCustomSlugToPages < ActiveRecord::Migration
  def change
    add_column :comfy_cms_pages, :custom_slug, :string
  end
end
