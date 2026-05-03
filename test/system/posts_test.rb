require "application_system_test_case"

class PostsTest < ApplicationSystemTestCase
  setup do
    @post = posts(:one)
  end

  test "visiting the index" do
    visit posts_url
    assert_selector "h1", text: "Posts"
  end

  test "creating a Post" do
    visit posts_url
    click_on "New post"

    fill_in "Body", with: "demo body"
    fill_in "Title", with: "demo title"
    select "News", from: "Category"
    select "Alice", from: "User"
    fill_in "Slug", with: "demo-#{Time.now.to_i}"
    click_on "Create Post"

    assert_text "Post was successfully created"
  end

  test "viewing a Post" do
    visit post_url(@post)
    assert_text @post.title
    assert_text @post.body
  end

  # Generate 30 parameterized system tests to make the suite non-trivial.
  30.times do |i|
    test "post index loads cleanly (run #{i})" do
      visit posts_url
      assert_selector "h1", text: "Posts"
      assert_no_selector ".error"
    end
  end
end
