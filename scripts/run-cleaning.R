if (file.exists("renv/activate.R")) {
  source("renv/activate.R")
}

cleaning_scripts <- c(
  "dwr/2026-06-19-v01" = "scripts/clean-dwr-2026-06-19-v01.R",
  "ebmud/2026-05-22-v01" = "scripts/clean-ebmud-2026-05-22-v01.R",
  "sbfca/2026-05-22-v01" = "scripts/clean-sbfca-2026-05-22-v01.R",
  "scwa/2026-05-22-v01" = "scripts/clean-scwa-2026-05-22-v01.R",
  "sfpuc/2026-05-22-v01" = "scripts/clean-sfpuc-2026-05-22-v01.R",
  "water-forum/2026-05-27-v01" = "scripts/clean-water-forum-2026-05-27-v01.R",
  "ywa/2026-05-23-v01" = "scripts/clean-ywa-2026-05-23-v01.R"
)

for (submission in names(cleaning_scripts)) {
  script <- cleaning_scripts[[submission]]

  if (!file.exists(script)) {
    stop("Cleaning script not found for ", submission, ": ", script, call. = FALSE)
  }

  message("Running ", submission, " via ", script)
  source(script, local = new.env(parent = globalenv()))
  message("Finished ", submission)
}

message("Finished ", length(cleaning_scripts), " cleaning script(s).")
