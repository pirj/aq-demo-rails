class AddPostsTagsJoinTable < ActiveRecord::Migration[8.1]
  def change
    create_join_table :posts, :tags do |t|
      t.references :posts, null: false, foreign_key: true
      t.references :tags, null: false, foreign_key: true
    end
  end
end
