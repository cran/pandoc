# About how to install version --------------------------------------------

with_download_cache <- function(version, bundle_name, code) {
  # download bundle
  # Caching the download for a session in a temp folder.
  # This is useful in tests suits
  tmp_folder <- fs::path_temp("r-pandoc-download", version)
  fs::dir_create(tmp_folder)
  owd <- setwd(tmp_folder)
  on.exit(setwd(owd), add = TRUE)
  if (!fs::file_exists(bundle_name)) {
    rlang::inform(c(" " = "Downloading bundle..."))
    force(code)
  } else {
    rlang::inform(c(" " = "Using cached bundle."))
  }
  fs::path_abs(bundle_name)
}

#' Install a pandoc binary for Github release page
#'
#' Binary releases of Pandoc are available on its release page. By default, this
#' function will install the latest available version.
#' `pandoc_install_nightly()` is a wrapper for `pandoc_install("nightly")`.
#' `pandoc_update()` is an alias for `pandoc_install()` default behavior.
#'
#' Pandoc versions are installed in user data directories with one folder per
#' version. See [pandoc_locate()].
#'
#' Only one nightly version is available at a time as there should be no need to
#' switch between them. The latest nightly will be installed over the current
#' one if any. Installing nightly version is useful for example to test a bug
#' against the very last available built version.
#'
#' @param version This can be either:
#'   * `"latest"` for the latest release
#'   * A version number (e.g `"2.11.4"`) for a specific version
#'   * `"nightly"` for the last pandoc development built daily
#' @param force To set to `TRUE` to force a re-installation
#' @return Invisibly, the path where the binary is installed otherwise. `NULL` if already
#'   installed.
#' @examplesIf rlang::is_interactive() && !pandoc::pandoc_is_installed("latest")
#' # Install the latest pandoc version
#' pandoc_install() # or pandoc_update()
#' pandoc_uninstall("latest")
#' @examplesIf rlang::is_interactive() && !pandoc::pandoc_is_installed("2.11.4")
#' # Install a specific pandoc version
#' pandoc_install("2.11.4")
#' pandoc_uninstall("2.11.4")
#' @name pandoc_install
#' @export
pandoc_install <- function(version = "latest", force = FALSE) {
  gh_required()

  if (version == "nightly") {
    return(pandoc_install_nightly())
  }

  # check if already installed while avoiding a gh request
  .is_already_installed <- function(version, call = caller_env()) {
    install_dir <- pandoc_home(version)
    if (fs::dir_exists(install_dir) && !length(fs::dir_ls(install_dir)) == 0L) {
      rlang::inform(c(
        v = sprintf("Pandoc %s already installed.", version),
        " " = "Use 'force = TRUE' to overwrite."
      ))
      return(invisible(TRUE))
    }
    invisible(FALSE)
  }
  if (!force && version != "latest" && .is_already_installed(version)) {
    return(invisible(NULL))
  }

  # get bundle download url
  release_bundle <- pandoc_release_asset(version)

  # Check if already installed now that "latest" is resolved
  if (!force && version == "latest" && .is_already_installed(release_bundle$version)) {
    return(invisible(NULL))
  }

  version <- release_bundle$version
  install_dir <- pandoc_home(version)
  if (force && fs::dir_exists(install_dir)) {
    fs::dir_delete(install_dir)
  }

  rlang::inform(c(i = paste0("Installing Pandoc release ", version)))
  bundle_name <- fs::path_file(release_bundle$url)
  tmp_file <- with_download_cache(version, bundle_name, {
    utils::download.file(release_bundle$url, destfile = bundle_name, quiet = TRUE)
  })

  # install bundle
  switch(fs::path_ext(release_bundle$url),
    gz = utils::untar(tmp_file, exdir = install_dir, tar = "internal"),
    zip = utils::unzip(tmp_file, exdir = install_dir, junkpaths = TRUE)
  )

  # For linux bundle, the pandoc binary can be in a nested bin folder
  # create a simlink to make it available at pandoc_locate() level
  bin <- fs::dir_ls(install_dir, recurse = TRUE, regexp = "bin/pandoc$")
  if (!rlang::is_empty(bin)) {
    bin <- bin[1]
    fs::link_create(bin, fs::path(install_dir, fs::path_file(bin)))
  }
  # Before Pandoc 2.11, pandoc-citeproc was shipped with pandoc bundle
  # On linux, we also need to create a simlink to make it available at pandoc_locate() level
  bin <- fs::dir_ls(install_dir, recurse = TRUE, regexp = "bin/pandoc-citeproc$")
  if (!rlang::is_empty(bin)) {
    bin <- bin[1]
    fs::link_create(bin, fs::path(install_dir, fs::path_file(bin)))
  }

  # check access right
  # MacOS is missing the executable bit (#1)
  bin <- fs::path(install_dir, "pandoc")
  if (pandoc_os() == "macOS" && !fs::file_access(bin, mode = "execute")) {
    fs::file_chmod(bin, "u+x")
  }

  rlang::inform(c(v = sprintf("Pandoc version %s installed.", version)))

  invisible(install_dir)
}



#' @rdname pandoc_install
#' @export
pandoc_update <- function() {
  rlang::inform(c(i = "Updating to last available Pandoc release"))
  invisible(pandoc_install(version = "latest"))
}

#' @rdname pandoc_install
#' @param n_last Set to `n` as integer to install the n-th from last nightly
#'   build. Default is last available build (1L)
#' @examplesIf rlang::is_interactive() && !pandoc::pandoc_is_installed("nightly")
#' # Install last nightly build of pandoc
#' pandoc_install_nightly()
#' pandoc_uninstall("nightly")
#' @export
pandoc_install_nightly <- function(n_last = 1L) {
  gh_required()
  os <- tolower(pandoc_os())
  bundle_name <- sprintf("nightly-%s", os)
  version <- "nightly"
  install_dir <- pandoc_home(version)
  rlang::inform(c(i = "Retrieving last available nightly informations..."))
  runs <- gh::gh("/repos/jgm/pandoc/actions/workflows/nightly.yml/runs",
    .limit = max(15L, n_last + 5)
  )
  runs <- keep(runs$workflow_runs, ~ .x$conclusion == "success")
  ind <- min(length(runs), n_last)
  artifacts_url <- runs[[ind]][["artifacts_url"]]
  head_sha <- runs[[ind]][["head_sha"]]
  artifacts <- gh::gh(artifacts_url)
  artifact_url <- keep(artifacts$artifacts, ~ .x$name == bundle_name)[[1]][["archive_download_url"]]
  if (fs::dir_exists(install_dir)) {
    current_version <- pandoc_nightly_version()
    if (head_sha == current_version) {
      rlang::inform(c(v = paste0("Last version already installed: ", current_version)))
      return(invisible(install_dir))
    }
    rlang::inform(c(i = paste0("Removing old Pandoc nightly version ", current_version)))
    fs::dir_delete(install_dir)
  }

  bundle_name <- fs::path_ext_set(head_sha, "zip")
  rlang::inform(c(i = "Installing last available nightly..."))
  tmp_file <- with_download_cache("nightly", bundle_name, {
    gh::gh(artifact_url, .destfile = bundle_name)
  })

  utils::unzip(tmp_file, exdir = install_dir, junkpaths = TRUE)
  rlang::inform(c(v = paste0("Last Pandoc nightly installed: ", pandoc_nightly_version())))
  # check access right
  # MacOS / Linux are missing the executable bit (#1)
  if (pandoc_os() %in% c("macOS", "linux") &&
    !fs::file_access(pandoc_bin("nightly"), mode = "execute")) {
    fs::file_chmod(pandoc_bin("nightly"), "u+x")
  }
  invisible(install_dir)
}

pandoc_nightly_version <- function() {
  nightly_home <- pandoc_home("nightly")
  readme <- fs::path(nightly_home, "README.nightly.txt")
  if (!fs::file_exists(readme)) {
    return(NULL)
  }
  x <- readLines(readme, n = 1L, encoding = "UTF-8")
  gsub("^Built from ([^[:space:]]*)\\s*$", "\\1", x, perl = TRUE)
}

.min_supported_version <- numeric_version("2.0.3")

pandoc_release_asset <- function(version, os = pandoc_os(), arch = pandoc_arch(os)) {
  releases <- pandoc_releases()
  if (version == "latest") {
    i <- 1L
    version <- releases[[1]]$tag_name
  } else {
    # special known cases
    if (os == "linux" && arch == "arm64" && numeric_version(version) < "2.12") {
      rlang::abort("Pandoc binaries for arm64 are available for 2.12 and above only")
    }
    if (os == "macOS" && arch == "arm64" && numeric_version(version) < "3.1.2") {
      rlang::abort("Pandoc binaries for arm64 on Mac are available for 3.1.2 and above only")
    }
    if (version == "2.2.3") {
      rlang::abort(c(
        "Pandoc 2.2.3 had a serious regression so binaries are no more available",
        "Download 2.2.3.1 instead."
      ))
    }

    versions <- map_chr(releases, "[[", "tag_name")
    i <- which(version == versions)
    if (length(i) == 0) {
      rlang::abort(sprintf("Pandoc version %s can't be found.", version))
    }
  }

  # we don't have common zip / tar.gz versions for all OS before
  version_num <- numeric_version(version)
  if (version_num < .min_supported_version) {
    rlang::abort(sprintf("Only version above %s can be installed with this package", .min_supported_version))
  }

  assets <- releases[[i]][["assets"]]
  names <- map_chr(assets, "[[", "name")

  bundle_name <- pandoc_bundle_name(version, os = os, arch = arch)

  i <- grep(bundle_name, names)

  if (length(i) == 0L) rlang::abort(sprintf("No release bundle with name '%s' available.", bundle_name))

  bundle_url <- assets[[i]][["browser_download_url"]]

  list(version = version, url = bundle_url)
}

pandoc_bundle_name <- function(version, os = pandoc_os(), arch = pandoc_arch(os)) {
  ext <- switch(os,
    linux = ".tar.gz",
    macOS = ,
    windows = ".zip"
  )
  r_os <- sprintf("(-%s)?", os)
  r_arch <- sprintf("(-%s)?", arch)
  r_os_arch <- paste0(r_os, r_arch)

  # Architecture is in bundle name since pandoc 3.1.2, and with another order
  if (os == "macOS") {
    if (as.numeric_version(version) < "3.1.2") {
    r_os_arch <- r_os
    } else {
      r_os_arch <- paste0(r_arch, r_os)
    }
  }

  regex <- paste0("pandoc-", version, "(-\\d)?", r_os_arch, ext)
  gsub("\\.", "\\\\.", regex)
}

pandoc_releases <- function() {
  default_cache <- function() {
    # set this option to use a cached version
    cached <- Sys.getenv("PANDOC_CACHE_GITHUB", NA_character_)
    if (!is.na(cached)) {
      # use same ~ on all OS
      if (fs::path_ext(cached) == "rds" && fs::file_exists(cached)) {
        rlang::inform(c(
          "i" = sprintf(
            "Using cached version '%s' in instead of fetching GH",
            fs::path_file(cached)
          )
        ))
        readRDS(cached)
      }
    } else {
      fetch_gh_releases()
    }
  }

  rlang::env_cache(the, "pandoc_releases", default_cache())
}

fetch_gh_releases <- function(limit = Inf) {
  gh_required()
  rlang::inform(c(i = "Fetching Pandoc releases info from github..."))
  gh::gh(
    "GET /repos/:owner/:repo/releases",
    owner = "jgm",
    repo = "pandoc",
    .limit = limit,
    .progress = FALSE
  )
}

pandoc_arch <- function(os = c("windows", "macOS", "linux")) {
  os <- rlang::arg_match(os)
  arch <- Sys.info()[["machine"]]
  if (os == "windows") {
    if (arch == "x86-64") {
      return("x86_64")
    }
  } else if (os == "linux") {
    if (arch == "x86_64") {
      return("amd64")
    }
    if (arch %in% c("aarch64", "arm64")) {
      return("arm64")
    }
  } else if (os == "macOS") {
    if (arch == "x86_64") {
      return("x86_64")
    }
    if (arch %in% c("aarch64", "arm64")) {
      return("arm64")
    }
  }
  rlang::abort("No binary bundle available for this architecture")
}

pandoc_os <- function() {
  os <- tolower(Sys.info()[["sysname"]])
  switch(os,
    darwin = "macOS",
    linux = "linux",
    windows = "windows",
    rlang::abort("Unknown operating system.")
  )
}

# nocov start
gh_required <- function() {
  rlang::check_installed(
    pkg = "gh",
    reason = "to install Pandoc from Github."
  )
}
# nocov end


# About installed versions -------------------------------------------------

#' Check Pandoc versions already installed
#'
#' * `pandoc_installed_versions()` lists all versions already installed
#' * `pandoc_installed_latest()` returns the most recent installed version
#' * `pandoc_is_installed()` allows to check for a specific installed version
#'
#' @return A character vector of installed versions or a logical for
#'   `pandoc_is_installed()`. It will return `NULL` is no versions are installed.
#' @examples
#' pandoc_installed_versions()
#' pandoc_installed_latest()
#' pandoc_is_installed("2.19.2")
#' @export
pandoc_installed_versions <- function() {
  pandoc_home <- pandoc_home()
  if (!fs::dir_exists(pandoc_home)) {
    return(NULL)
  }
  versions <- fs::path_file(fs::dir_ls(pandoc_home, type = "directory"))
  if (rlang::is_empty(versions)) {
    return(NULL)
  }
  is_nightly <- "nightly" %in% versions
  versions <- setdiff(versions, "nightly")
  sorted_versions <- sort(as.numeric_version(versions), TRUE)
  c(if (is_nightly) "nightly", as.character(sorted_versions))
}

#' @rdname pandoc_installed_versions
#' @examples
#' pandoc_installed_latest()
#' @export
pandoc_installed_latest <- function() {
  installed_versions <- setdiff(pandoc_installed_versions(), "nightly")
  if (is.null(installed_versions)) {
    return(NULL)
  }
  as.character(max(as.numeric_version(installed_versions)))
}

#' @rdname pandoc_installed_versions
#' @inheritParams pandoc_install
#' @param error if `TRUE` an error will be raised if the result is `FALSE`
#' @param ask if `TRUE`, the user will be prompt in an interactive
#' @return For `pandoc_is_installed()`, `TRUE` if only the required version is
#'   installed. If `FALSE` and `ask` is `TRUE`, the user will be prompt for
#'   installing the version.
#' @export
pandoc_is_installed <- function(version, error = FALSE, ask = FALSE) {
  if (pandoc_is_external_version(version)) {
    rlang::abort("Only version install with this package can be checked, not external versions.")
  }
  installed <- version %in% pandoc_installed_versions()
  if (!installed) {
    if (ask) {
      if (!rlang::is_interactive()) {
        rlang::abort("User input required, but session is not interactive.")
      }
      rlang::inform(c(
        "i" = sprintf("Version '%s' is not yet installed", version),
        "!" = "Would you like to install it ?"
      ))
      if (utils::menu(c("yes", "no")) == 1L) {
        pandoc_install(version)
        installed <- TRUE
      }
    }
    if (error && !installed) {
      rlang::abort(sprintf("Version '%s' is not yet installed", version))
    }
  }
  installed
}

#' Uninstall a Pandoc version
#'
#' You can run [pandoc_installed_versions()] to see which versions are
#' currently installed on the system.
#'
#' @param version which version to uninstalled.
#'
#' @return `TRUE` (invisibly) if uninstalling is successful.
#'
#' @seealso [pandoc_install()]
#' @examplesIf rlang::is_interactive() && !pandoc::pandoc_is_installed("2.19.2")
#' pandoc_install("2.19.2")
#' pandoc_is_installed("2.19.2")
#' pandoc_uninstall("2.19.2")
#' @export
pandoc_uninstall <- function(version) {
  if (rlang::is_missing(version)) {
    rlang::abort(c(
      "Provide a version to uninstall.",
      "Run `pandoc_installed_versions()` to see installed versions."
    ))
  }
  install_dir <- pandoc_locate(version)
  if (!is.null(install_dir)) {
    # Remove installation folder
    fs::dir_delete(install_dir)
    # Deal with active version
    if (pandoc_is_active(version)) {
      # Change the active version
      latest <- pandoc_installed_latest()
      if (is.null(latest)) {
        # no more version installed
        the$active_version <- ""
      } else {
        # Change to the latest version
        the$active_version <- latest
      }
    }
  }
  invisible(TRUE)
}

#' @importFrom rappdirs user_data_dir
#' @noRd
pandoc_home <- function(version = NULL) {
  if (is_devmode() || on_rcmd_check()) {
    old <- Sys.getenv("R_USER_DATA_DIR")
    Sys.setenv(R_USER_DATA_DIR = tempdir())
    on.exit(Sys.setenv(R_USER_DATA_DIR = old))
  }
  rappdirs::user_data_dir("r-pandoc", version = version)
}

#' Fetch all versions available to install
#'
#' This function will fetch information from Github
#' <https://github.com/jgm/pandoc> about available Pandoc versions released.
#'
#' @return character vector of all available release.
#'
#' @seealso [pandoc_install()], [pandoc_installed_versions()]
#' @examplesIf rlang::is_installed("gh") && attr(curlGetHeaders("https://github.com"), "status") == "200"
#' @export
pandoc_available_releases <- function() {
  releases <- pandoc_releases()
  versions <- map_chr(releases, "[[", "tag_name")
  keep(versions, ~ numeric_version(.x) >= .min_supported_version)
}

pandoc_is_external_version <- function(version) {
  version %in% the$external_versions
}

#' Is a pandoc version active ?
#'
#' @inheritParams pandoc_install
#'
#' @return `TRUE` is the `version` provided is currently the active one (i.e the one used when special `"default"` keyword is used).
#'
#' @seealso [`pandoc_bin()`]
#'
#' @examples
#' # is Pandoc 2.19.2 active ?
#' pandoc_is_active("2.19.2")
#' # is it the Pandoc in PATH which is active ?
#' pandoc_is_active("system")
#' @export
pandoc_is_active <- function(version) {
  version <- resolve_version(version)
  version == the$active_version
}

#' Locate a specific Pandoc version installed with this package
#'
#' This package helps install and manage Pandoc binaries in a specific folder.
#' This function helps with finding the path to those specific versions of Pandoc.
#' See [pandoc_bin()] for another way of getting paths to `pandoc` binaries
#'
#' @inheritParams pandoc_bin
#' @return Path of Pandoc binaries root folder if version is available.
#' @seealso [pandoc_install()]
#' @examplesIf pandoc::pandoc_available() && !pandoc::pandoc_is_active("system") && !pandoc::pandoc_is_active("rstudio")
#' # where is the default active version located ?
#' pandoc_locate()
#' @examples pandoc::pandoc_is_installed("2.11.4")
#' # where is a specific installed version located
#' pandoc_locate("2.11.4")
#' @examples
#' # return root folder of installed versions
#' pandoc_locate(NULL)
#' @export
pandoc_locate <- function(version = "default") {
  if (is.null(version)) {
    return(pandoc_home(NULL))
  }
  if (!is.character(version) && length(version) != 1L) {
    rlang::abort("version must be a length one character")
  }
  version <- resolve_version(version)
  # Binaries installed and managed by this package
  if (is.null(version) || !nzchar(version)) {
    rlang::warn("No Pandoc version available.")
    return(NULL)
  }
  # Special binaries not managed by this package
  if (pandoc_is_external_version(version)) {
    rlang::abort("Use `pandoc_bin()` directly when using externally installed Pandoc version.")
  }
  home_dir <- pandoc_home(version)
  if (!fs::dir_exists(home_dir)) {
    return(NULL)
  }
  home_dir
}
