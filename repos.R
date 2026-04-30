
# script to update repos.json file

library(gh)
library(jsonlite)

# get repo names
repos <- gh("GET /orgs/{org}/repos", org = "ices-advice", .limit = Inf)

repo_names <- sapply(repos, "[[", "name")
repo_names <- repo_names[repo_names != ".github"]

repo <- repo_names[1]

get_dirs <-
  function(repo, org = "ices-advice") {
    items <- gh("GET /repos/{org}/{repo}/contents", org = org, repo = repo)
    dir <- function(item) if (item$type == "dir") item$name else NULL

    unlist(lapply(items, dir))
  }

get_subdirs <-
  function(repo, org = "ices-advice", subdir) {
    items <- gh("GET /repos/{org}/{repo}/contents/{subdir}", org = org, repo = repo, subdir = subdir)
    dir <- function(item) if (item$type == "dir") item$name else NULL

    unlist(lapply(items, dir))
  }

get_taf_dir <-
  function(advice_dir) {
    taf_dirs <- get_dirs(advice_dir, org = "ices-taf")
    if (any(taf_dirs %in% c("boot", "bootstrap"))) {
      list(name = advice_dir)
    } else {
      subdirs <- lapply(taf_dirs, get_subdirs, repo = advice_dir, org = "ices-taf")
      is.taf <- sapply(subdirs, function(x) any((x %||% "") %in% c("boot", "bootstrap")))
      if (!any(is.taf)) {
        list(name = advice_dir)
      } else {
        list(name = advice_dir, subdir = taf_dirs[is.taf][1])
      }
    }
  }

make_record <-
  function(repo) {
    print(repo)
    year <- substring(repo, 1, 4)
    if (year == "2026") return(NULL)
    advice_dirs <- get_dirs(repo)

    list(
      repo_name = repo,
      publish_after_utc = "2026-01-01 01:00",
      repos = lapply(advice_dirs, get_taf_dir)
    )
  }


repos_json <- lapply(rev(sort(repo_names)), make_record)
repos_json <- repos_json[!sapply(repos_json, is.null)]

repos_current <- read_json("repos.json")

keep <- !sapply(repos_json, "[[", "repo_name") %in% sapply(repos_current, "[[", "repo_name")

new_json <- toJSON(c(repos_current, repos_json[keep]), pretty = TRUE, auto_unbox = TRUE)
new_json

cat(new_json, file = "repos_new.json")
