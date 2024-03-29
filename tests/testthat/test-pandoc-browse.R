test_that("url_view", {
  expect_snapshot(url_view("https://example.org/"))
})

test_that("pandoc_browse_release()", {
  skip_if_not_installed("gh")
  skip_if_offline()
  skip_on_cran()
  # trick to cache releases if not yet to avoid message
  suppressMessages(pandoc_releases())
  expect_snapshot(pandoc_browse_release())
  expect_snapshot(pandoc_browse_release("2.7.3"))
  expect_error(pandoc_browse_release("0.1"))
})

test_that("pandoc_browse_manual()", {
  expect_snapshot(pandoc_browse_manual())
  expect_snapshot(pandoc_browse_manual("description"))
})

test_that("pandoc_browse_extension()", {
  expect_snapshot(pandoc_browse_extension("smart"))
})

test_that("pandoc_browse_citation()", {
  expect_snapshot(pandoc_browse_citation())
})

test_that("pandoc_browse_exit_code()", {
  expect_snapshot(pandoc_browse_exit_code())
})

test_that("pandoc_browse_option()", {
  expect_snapshot(pandoc_browse_option())
  expect_snapshot(pandoc_browse_option("quiet"))
  expect_snapshot(pandoc_browse_option("--quiet"))
})
