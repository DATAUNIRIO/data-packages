library(gh)
library(dplyr)
library(purrr)
library(stringi)
library(readr)

get_tag <- function(rd, tag) {
  x <- tools:::.Rd_get_metadata(rd, kind = tag)
  if (!length(x)) return(NA_character_)
  x <- x[nchar(x) > 0]
  x
}

pkgs <- readRDS("data/pkg_data_data.rds")
pkgs_with_data <- pkgs$pkg_name[pkgs$has_data_dir]

saved_gh_data_rd_files <- "data/data_rd_gh_search_results.rds"
if (file.exists(saved_gh_data_rd_files)) {
  pkgs_data_rds_saved <- readRDS("data/data_rd_gh_search_results.rds")
  start = length(pkgs_data_rds_saved) + 1
} else {
  start = 1
}

pkgs_data_rds <- lapply(pkgs_with_data[start:length(pkgs_with_data)], function(pkg_name) {
  message(pkg_name)
  Sys.sleep(2)
  query <- sprintf( "repo:cran/%s extension:Rd docType{data", pkg_name)
  res <- tryCatch(gh("GET /search/code", q = query), 
                  error = function(e) {
                    if(any(stri_detect_fixed(e, "403 Forbidden"))) {
                      # Should really check rate limit API and restart then
                      # But easiest to just stop and manually restart later
                      stop("Rate limit exceeded.")
                    }
                    NULL
                  })
  res
})

if (exists("pkgs_data_rds_saved")) {
  pkgs_data_rds <- c(pkgs_data_rds_saved, pkgs_data_rds)
}
saveRDS(pkgs_data_rds, saved_gh_data_rd_files)


## Download and parse the Rd files
rd_file_meta <- lapply(pkgs_data_rds[1:1000], function(a) {
  if (!length(a$items)) return(NULL)
  lapply(a$items, function(x) {
  tryCatch({
    reponame <- x$repository$name
    repo_url <- paste0("https://github.com/cran/", reponame)
    dataset_rd <- gsub("\\.Rd$", "", x$name)
    dataset_rd_url <- gsub("github\\.com", "raw.githubusercontent.com", x$html_url)
    dataset_rd_url <- gsub("/blob/", "/", dataset_rd_url)
    rd_text <- readr::read_lines(dataset_rd_url)
    tc <- textConnection(rd_text)
    ret <- list(name = reponame, 
         repo_url = repo_url, 
         dataset_rd_url = dataset_rd_url, 
         rd_text = rd_text,
         rd_text_parsed = tools::parse_Rd(tc)
    )
    close(tc)
    ret
  }, error = function(e) NULL)
  })
}) %>% 
  flatten() %>% 
  compact()

saveRDS(rd_file_meta, "data/rd_file_contents.rds")

## Combine parsed Rd file info into a data frame
rd_metadata <- map_df(rd_file_meta, function(x) {
  if (is.null(x)) return(NULL)
  data_frame(pkg_name = x$name, 
             dataset_name = get_tag(x$rd_text_parsed, "name"), 
             # dataset_alias = get_tag(x$rd_text_parsed, "alias"), # May be better to not include this as it is sometimes not used appropriately
             dataset_title = paste(get_tag(x$rd_text_parsed, "title"), collapse = " "), 
             dataset_description = paste(get_tag(x$rd_text_parsed, "description"), collapse = " "), 
             dataset_format = paste(get_tag(x$rd_text_parsed, "format"), collapse = " "),
             dataset_source = paste(get_tag(x$rd_text_parsed, "source"), collapse = " "),
             dataset_reference = paste(get_tag(x$rd_text_parsed, "references"), collapse = " "),
             dataset_has_examples = ifelse(all(is.na(get_tag(x$rd_text_parsed, "examples"))), FALSE, TRUE), 
             dataset_has_links = any(grepl("\\\\code\\{\\\\link", x$rd_text))
  )
})

write_csv(rd_metadata, "data/data_rd_metadata.csv")
