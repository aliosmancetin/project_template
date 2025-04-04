if (Sys.getenv("RSTUDIO") == "1") {
  # Path to the env_vars.sh script
  env_vars_script <- file.path(getwd(), "workflow/00_env/env_vars.sh")

  # Variables to retrieve
  vars_to_get <- c(
    "PROJ_GUIX_PROFILE_DIR",
    "PROJ_R_LIBS_DIR",
    "R_USER_CACHE_DIR",
    "R_USER_CONFIG_DIR",
    "R_USER_DATA_DIR"
  )

  # Get other project related env vars
  selected_env_vars_names <- c(
  )
  names(selected_env_vars_names) <- selected_env_vars_names

  vars_to_get <- c(vars_to_get, selected_env_vars_names)

  delimiter <- "###ENV_VAR_DELIMITER###"

  # Build the shell command
  cmd_vars <- paste(
    sprintf(
      'printf "%%s%s%%s\\n" "%s" "${%s}"', delimiter, vars_to_get, vars_to_get
    ),
    collapse = "; "
  )

  cmd <- sprintf(
    'bash -c \'source "%s" >/dev/null 2>&1; %s\'', env_vars_script, cmd_vars
  )

  # Execute the command and capture the output
  env_output <- system(cmd, intern = TRUE, ignore.stderr = TRUE)

  if (length(env_output) > 0) {
    # Split each line at the delimiter
    env_vars_split <- strsplit(env_output, delimiter, fixed = TRUE)

    # Extract variable names and values
    env_names <- sapply(env_vars_split, `[`, 1)
    env_values <- sapply(env_vars_split, `[`, 2)

    # Create a named character vector
    env_list <- sapply(env_vars_split, function(x) {
      y <- x[2]
      names(y) <- x[1]
      y
    })

    # Use PROJ_R_LIBS_DIR to set .libPaths()
    proj_guix_profile_dir <- env_list["PROJ_GUIX_PROFILE_DIR"]
    guix_profile_site_lib <- file.path(
      proj_guix_profile_dir, "main_profile", "main_profile", "site-library"
    )

    proj_rlibs_dir <- env_list["PROJ_R_LIBS_DIR"]
    additional_site_lib <- file.path(proj_rlibs_dir, "main_profile")

    if (dir.exists(guix_profile_site_lib) && dir.exists(additional_site_lib)) {
      .libPaths(c(additional_site_lib, guix_profile_site_lib))
    } else if (dir.exists(guix_profile_site_lib)) {
      .libPaths(c(guix_profile_site_lib))
    } else {
      warning("PROJ_GUIX_PROFILE_DIR is not set.")
    }
  } else {
    warning(
      "Failed to retrieve required environment variables from env_vars.sh."
    )
  }

  print(".libPaths() was set based on main_profile!")
  print(.libPaths())

  # Set R_USER_CACHE_DIR, R_USER_CONFIG_DIR, R_USER_DATA_DIR
  Sys.setenv(
    R_USER_CACHE_DIR = env_list["R_USER_CACHE_DIR"],
    R_USER_CONFIG_DIR = env_list["R_USER_CONFIG_DIR"],
    R_USER_DATA_DIR = env_list["R_USER_DATA_DIR"]
  )

  # Set CURL_CA_BUNDLE, SSL_CERT_FILE, SSL_CERT_DIR
  Sys.setenv(
    CURL_CA_BUNDLE = file.path(env_list["PROJ_GUIX_PROFILE_DIR"], "main_profile", "main_profile", "etc", "ssl", "certs", "ca-certificates.crt"),
    SSL_CERT_FILE = file.path(env_list["PROJ_GUIX_PROFILE_DIR"], "main_profile", "main_profile", "etc", "ssl", "certs", "ca-certificates.crt"),
    SSL_CERT_DIR = file.path(env_list["PROJ_GUIX_PROFILE_DIR"], "main_profile", "main_profile", "etc", "ssl", "certs")
  )


  # Set selected env_vars as environment variable
  if (length(selected_env_vars_names) > 0) {

    env_vars <- lapply(
      selected_env_vars_names,
      function(var_name) env_list[[var_name]]
    )

    do.call(Sys.setenv, env_vars)

    rm(
      list = ls(all.names = TRUE)[
        !ls(all.names = TRUE) %in% "env_vars"
      ]
    )

  } else {
    rm(list = ls(all.names = TRUE))
  }

}
