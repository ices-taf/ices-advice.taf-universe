
# script to check the stocks in an advice release against ices-taf, and add
# those with publishable code to repos.json
#
# edit the settings below for each release, then from the repo root run:
#
#   Rscript release_stocks.R           # report only
#   Rscript release_stocks.R --apply   # report and add passing stocks to repos.json
#
# requires the gh command line tool, authenticated with read access to ices-taf
#
# a push of repos.json to main starts the publish workflow, so this script does
# not commit or push

library(jsonlite)

# release settings -------------------------------------------------------------

year <- 2026
publish_after_utc <- "2026-10-30 08:00"

# stock codes, * is a wildcard
stocks <- c("nep.fu.*", "nep.27.*", "whg.27.6a", "whg.27.7a", "lez.27.6b")

# repos with fewer functional lines of code than this are treated as templates
min_code_lines <- 20

source_org <- "ices-taf"
target_org <- "ices-advice"

# github -----------------------------------------------------------------------

gh_api <-
  function(...) {
    out <- suppressWarnings(system2("gh", c("api", ...), stdout = TRUE, stderr = FALSE))
    if (!is.null(attr(out, "status"))) return(NULL)
    out
  }

list_repos <-
  function(org) {
    out <- gh_api(
      "--paginate", shQuote(paste0("orgs/", org, "/repos?per_page=100&type=all")),
      "--jq", shQuote(".[] | select(.archived | not) | [.name, .default_branch] | @tsv")
    )
    if (is.null(out)) stop("could not list repos in ", org, ", check gh auth status")
    x <- strsplit(out, "\t")
    data.frame(name = sapply(x, "[", 1), branch = sapply(x, "[", 2))
  }

get_files <-
  function(repo, branch) {
    out <- gh_api(paste0("repos/", source_org, "/", repo, "/git/trees/", branch, "?recursive=1"))
    if (is.null(out)) return(NULL)
    tree <- fromJSON(paste(out, collapse = "\n"))
    if (isTRUE(tree$truncated)) warning(repo, ": file listing truncated")
    tree$tree[tree$tree$type == "blob", ]
  }

get_blob <-
  function(repo, sha) {
    gh_api(
      "-H", shQuote("Accept: application/vnd.github.raw"),
      paste0("repos/", source_org, "/", repo, "/git/blobs/", sha)
    )
  }

# code checks ------------------------------------------------------------------

is_script <- function(path) grepl("\\.(r|rmd|qmd|rnw)$", path, ignore.case = TRUE)

# keep only the code chunks of notebooks
code_chunks <-
  function(lines) {
    fence <- grepl("^\\s*(```|<<.*>>=|@\\s*$)", lines)
    lines[!fence & cumsum(fence) %% 2 == 1]
  }

# lines that do something, so not blank lines, comments or the setup that is
# all a template contains
functional_lines <-
  function(lines, path) {
    if (!grepl("\\.r$", path, ignore.case = TRUE)) lines <- code_chunks(lines)
    boilerplate <- paste0(
      "^\\s*(#.*|[{}()]*|(library|require|suppressMessages|suppressPackageStartupMessages|",
      "taf\\.library|taf\\.bootstrap|taf\\.boot|mkdir|rm|source|sourceTAF|sourceAll|",
      "source\\.all|graphics\\.off|setwd|clean)\\(.*)$"
    )
    sum(!grepl(boilerplate, lines))
  }

# the workflow only keeps these files from a folder it is publishing, so code
# anywhere else never reaches ices-advice
published_scripts <-
  function(paths, subdir = "") {
    prefix <- if (nzchar(subdir)) paste0(subdir, "/") else ""
    rel <- substring(paths, nchar(prefix) + 1)
    keep <- startsWith(paths, prefix) & is_script(paths) &
      (!grepl("/", rel) | grepl("^(boot|bootstrap)/[^/]+$", rel))
    paths[keep]
  }

# a taf analysis kept in a subfolder of the repo
find_subdir <-
  function(paths) {
    boot <- grep("^[^/]+/(boot|bootstrap)/", paths, value = TRUE)
    if (length(boot)) sub("/.*", "", boot[1]) else ""
  }

check_repo <-
  function(repo, branch) {
    message("checking ", repo)
    result <- data.frame(
      repo = repo, status = "empty", code_lines = 0, scripts = 0,
      scripts_not_published = 0, subdir = ""
    )

    files <- get_files(repo, branch)
    if (is.null(files) || !nrow(files)) return(result)

    paths <- files$path
    subdir <- ""
    if (!length(published_scripts(paths))) subdir <- find_subdir(paths)
    keep <- published_scripts(paths, subdir)

    lines <- sapply(keep, function(path) {
      functional_lines(get_blob(repo, files$sha[files$path == path]), path)
    })

    result$code_lines <- sum(unlist(lines))
    result$scripts <- length(keep)
    result$scripts_not_published <- sum(is_script(paths)) - length(keep)
    result$subdir <- subdir
    result$status <-
      if (!length(keep)) {
        "no code"
      } else if (result$code_lines < min_code_lines) {
        "template"
      } else {
        "publish"
      }
    result
  }

# repos.json -------------------------------------------------------------------

# repo names are {year}_{stock}_{suffix}, the suffix being optional
stock_of <- function(repo) sub("^[0-9]{4}_([^_]+)(_.*)?$", "\\1", repo)

set_of <- function(repo) sub("^([0-9]{4}_[^_]+)(_.*)?$", "\\1", repo)

check_current <-
  function(current) {
    names <- sapply(current, "[[", "repo_name")
    dups <- unique(names[duplicated(names)])
    if (length(dups)) warning("repeated in repos.json: ", paste(dups, collapse = ", "))
  }

format_set <-
  function(set, rows) {
    repos <- lapply(seq_len(nrow(rows)), function(i) {
      repo <- list(name = rows$repo[i])
      if (nzchar(rows$subdir[i])) repo$subdir <- rows$subdir[i]
      repo
    })
    record <- list(repo_name = set, publish_after_utc = publish_after_utc, repos = repos)
    paste0("  ", gsub("\n", "\n  ", toJSON(record, pretty = TRUE, auto_unbox = TRUE)))
  }

# add to the end of the text, to leave the existing entries as they are
add_sets <-
  function(new_sets, file = "repos.json") {
    lines <- readLines(file)
    end <- max(which(lines == "]"))
    lines <- lines[seq_len(end - 1)]
    lines[length(lines)] <- paste0(lines[length(lines)], ",")
    text <- c(lines, paste(new_sets, collapse = ",\n"), "]")
    fromJSON(paste(text, collapse = "\n"), simplifyVector = FALSE)
    con <- file(file, "wb")
    on.exit(close(con))
    writeLines(text, con, sep = "\n")
  }

# run --------------------------------------------------------------------------

apply <- "--apply" %in% commandArgs(trailingOnly = TRUE)

repos <- list_repos(source_org)
repos <- repos[startsWith(repos$name, paste0(year, "_")), ]
repos <- repos[grepl(paste(sapply(stocks, glob2rx), collapse = "|"), stock_of(repos$name)), ]
repos <- repos[order(repos$name), ]

results <- do.call(rbind, Map(check_repo, repos$name, repos$branch))
rownames(results) <- NULL

current <- read_json("repos.json")
check_current(current)
listed <- sapply(current, "[[", "repo_name")

results$set <- set_of(results$repo)
results$in_repos_json <- results$set %in% listed
results$in_target_org <- results$set %in% list_repos(target_org)$name

print(results[c(
  "repo", "status", "code_lines", "scripts", "scripts_not_published",
  "subdir", "in_repos_json", "in_target_org"
)], right = FALSE)

matched <- sapply(stocks, function(s) any(grepl(glob2rx(s), stock_of(results$repo))))
if (!all(matched)) message("no ", year, " repo found for: ", paste(stocks[!matched], collapse = ", "))

to_add <- results[results$status == "publish" & !results$in_repos_json, ]
new_sets <- sapply(unique(to_add$set), function(set) format_set(set, to_add[to_add$set == set, ]))

message("\n", length(new_sets), " stock(s) to add with publish_after_utc ", publish_after_utc)

if (apply && length(new_sets)) {
  add_sets(new_sets)
  message("repos.json updated, review it then commit and push to publish")
} else if (length(new_sets)) {
  message("report only, run with --apply to update repos.json")
}
