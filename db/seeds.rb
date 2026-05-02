# Seed enough records that db:seed has measurable wall clock.
50.times do |i|
  post = Post.create!(title: "Post #{i}", body: "Body of post #{i}. " * 20)
  3.times do |j|
    Comment.create!(post: post, body: "Comment #{j} on post #{i}.")
  end
end
puts "Seeded #{Post.count} posts and #{Comment.count} comments."
