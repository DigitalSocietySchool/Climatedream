#####################################
# ENVIRONMENT
#####################################
library(rstudioapi)
setwd(dirname(getSourceEditorContext()$path))

library(tidyverse)
library(rvest)
library(XML)
library(jsonlite)
library(RCurl)

options(stringsAsFactors = FALSE)

#####################################
# UTILS
#####################################
check_length <- function(data, len){
  if(length(data) > len) data[1:len] %>% return
  else if(length(data) == len) data %>% return
  else if(length(data) < len) c(data, rep('', len-length(data))) %>% return
  else rep('', len) %>% return
}
clean <- function(vector){
  vector <- vector[!is.null(vector)]
  vector <- vector[!is.na(vector)]
  vector <- vector[vector!='NA']
  vector <- vector[vector!='']
  return(vector)
}

# WARNING
# Result differ each time it's run!
get_reco <- function(video_id){
  print('get_reco()')
  print(video_id)
  html <- paste0('https://www.youtube.com/watch?v=',video_id) %>% read_html
  html %>% as.character %>% write('temp.html')
  txt <- readLines('temp.html')
  
  # Find JSON
  trial <- 0
  while(trial < 5){
    trial <- trial +1
    watch_next <- NA
    for(i in 1:length(txt)){
      if(grepl('RELATED_PLAYER_ARGS', txt[i])) {
        json <- gsub("^ *'RELATED_PLAYER_ARGS': *|,$", '', txt[i]) %>% fromJSON
        watch_next <- json$watch_next_response %>% fromJSON
        watch_next <- watch_next$contents$twoColumnWatchNextResults$secondaryResults$secondaryResults$results
        break
      }
    }
    if(!is.na(watch_next)) gsub('^.*watch.*=','', watch_next$compactVideoRenderer$videoId[3:20]) %>% 
      unique %>% clean %>% return
  }
  c() %>% return
}
get_channel_from_id <- function(id_list){
  res <- c()
  for(id in id_list){
    channel <- 'Unknown'
    url <- paste0('https://www.youtube.com/channel/',id)
    if(url.exists(url)){ 
      channel <- url %>% read_html %>% html_nodes('meta[name="title"]') %>% html_attr('content')
      channel <- gsub('\t','',channel)
    }
    res <- c(res, channel)
    print(channel)
  }
  res %>% return
}
# 
# 
# # Get channel name
# if(nchar(channel_id) == 24){
#   channel_url <- paste0('https://www.youtube.com/channel/', channel_id)
#   if(! url.exists(channel_url)) {
#     paste('Channel 404\t',channel_url) %>% print
#     channel <- 'Unknown'
#   } else {
#     channel <- read_html(channel_url) %>% html_nodes('meta[name=title]') %>% html_attr('content')
#     channel <- gsub('\t','',channel)
#   }
# } else {
#   channel <- 'Unknown'
# }
#####################################
# GET DATA
#####################################
#AnalysisFiles is a folder containing the current data to be analysed
files <- list.files('AnalysisFiles/')
files <- files[grepl('tsv$',files)]
files <- paste0('AnalysisFiles/', files)

# sample <-  c("al gore", "anthropogenic climate", "atmospheric co2", "climate science", "co2 emissions", "co2 levels", "global climate", "global cooling", "global temperature", "global warming", "greenhouse gases", "ice age", "industrial revolution", "oil companies", "patrick moore", "scientific method", "sea level")
# sample <- gsub(' ', '', sample)

data <- data.frame()
for(f in files){
  # Select a subset of the session (if relevant)
  # session <- gsub('^results.*results_|_2020.*$', '', f)
  # if(! session %in% sample) next
  # print(session)
  
  d <- read.csv(f, sep='\t', quote = "", row.names = NULL, stringsAsFactors = FALSE)
  
  # Verify that video IDs are valid
  test <- gsub('^.*=', '', d$video_id) %>% clean %>% nchar
  if(FALSE %in% c(test == 11)) next
  
  data <- rbind(data, d)
  d %>% glimpse 
}

data %>% glimpse


##### List of queries
queries <- data$keyword_ref %>% unique
##### Complete list of video IDs
video_id <- data$video_id %>% unique
reco_video_id <- data$reco_videos_id %>% str_split(' *; *') %>% unlist %>% unique
video_all <- c(video_id, reco_video_id) 
video_all <- gsub('^.*=','', video_all) %>% clean %>% unique 


#####################################
# MAKE NODES 
#####################################
#####  Loop through videos #####
# nodes_backup <- nodes
nodes <- data.frame() 

# If the script is interrupted, restart the loop where it stopped with this line of code:
# for(v in video_all[nrow(nodes)+1:length(video_all)]){
for(v in video_all){
  print(v)
  
  occurence <- data %>% filter(video_id == v) # %>% slice(1)
  occurence_reco <- data %>% filter(grepl(v, reco_videos_id)) # %>% slice(1)
  n_occ <- nrow(occurence) + nrow(occurence_reco)
  
  # Watched
  if(nrow(occurence)!=0){
    session <- occurence$keyword_ref[1]
    session_direct <- occurence$keyword_ref %>% paste(collapse = ';')
    session_all <- c(occurence$keyword_ref) %>% paste(collapse = ';') 
    iteration_all <- c(as.character(occurence$iteration)) %>% paste(collapse = ';')
    session_from_reco <- c(occurence_reco$keyword_ref, occurence$keyword_ref) %>% paste(collapse = ';') 
    group <- occurence$keyword_ref[1]
    title <- occurence$title[1]
    description <- occurence$description[1]
    keywords <- occurence$keywords[1]
    genre <- occurence$genre[1]
    date <- occurence$date_publication[1]
    channel_id <- occurence$channel_id[1]
    channel <- get_channel_from_id(channel_id)
    views <- occurence$views[1]
    duration <- occurence$duration[1]
    
    # Not watched  
  } else { 
    session <- occurence_reco$keyword_ref[1]
    session_direct <- ''
    session_all <- occurence_reco$keyword_ref %>% paste(collapse = ';')
    iteration_all <- as.character(occurence_reco$iteration) %>% paste(collapse = ';')
    session_from_reco <- ''
    group <- 'recommendation'
    
    # Scrape video info 
    url_video <- paste0('https://www.youtube.com/watch?v=', v)
    if(url.exists(url_video)) {
      html <- url_video %>% read_html
      
      title <- html %>% html_nodes('meta[name=title]') %>% html_attr('content')
      title <- gsub('\t','',title)
      
      description <- html %>% html_nodes('meta[name=description]') %>% html_attr('content')
      description <- gsub('\t','',description)
      
      keywords <- html %>% html_nodes('meta[name=keywords]') %>% html_attr('content')
      keywords <- gsub('\t','',keywords)
      keywords <- gsub(',', ';', keywords)
      
      genre <- html %>% html_nodes('meta[itemprop="genre"]') %>% html_attr('content')
      genre <- gsub(',', ';', genre)
      
      date <- html %>% html_nodes('meta[itemprop="datePublished"]') %>% html_attr('content')
      channel_id <- html %>% html_nodes('meta[itemprop="channelId"]') %>% html_attr('content')
      channel <- get_channel_from_id(channel_id)
      views <- html %>% html_nodes('meta[itemprop="interactionCount"]') %>% html_attr('content')
      duration <- html %>% html_nodes('meta[itemprop="duration"]') %>% html_attr('content')
    } else {
      sample <- occurence_reco %>% slice(1)
      temp_list <- sample$reco_videos_id %>% str_split(' *; *') %>% unlist 
      index <- match(v, temp_list)
      
      temp_list <- sample$reco_titles %>% str_split(' *; *') %>% unlist 
      title <- temp_list[index]
      
      temp_list <- sample$reco_snippets %>% str_split(' *; *') %>% unlist 
      description <- temp_list[index]
      
      keywords <- genre <- date <- ''
      
      temp_list <- sample$reco_channels_id %>% str_split(' *; *') %>% unlist 
      channel_id <- temp_list[index]
      
      temp_list <- sample$reco_channels_name %>% str_split(' *; *') %>% unlist 
      channel <- temp_list[index]
      
      temp_list <- sample$reco_views %>% str_split(' *; *') %>% unlist 
      views <- temp_list[index]
      
      temp_list <- sample$reco_durations %>% str_split(' *; *') %>% unlist 
      duration <- temp_list[index]
      
    }
  } 
  
  # # Format sessions list
  # session_all <- session_all %>% str_split(' *; *') %>% unlist %>% clean %>% unique %>% paste(collapse = ';') 
  # if(session_all == '') break
  
  # Format views 
  views <- gsub('[^0-9]','', views)
  if(length(views) == 0) views <- '0'
  if(is.null(views)) views <- '0'
  if(is.na(views)) views <- '0'
  if(views=='') views <- '0'
  
  # Format channel_id 
  if(length(channel_id) == 0) channel_id <- ''
  if(is.null(channel_id)) channel_id <- ''
  if(is.na(channel_id)) channel_id <- ''
  
  # Verif fields
  title <- title %>% check_length(1)
  description <- description %>% check_length(1)
  keywords <- keywords %>% check_length(1)
  genre <- genre %>% check_length(1)
  date <- date %>% check_length(1)
  channel <- channel %>% check_length(1)
  channel_id <- channel_id %>% check_length(1)
  duration <- duration %>% check_length(1)
  
  line <- data.frame(id=v, session=session, 
                     session_direct=session_direct, session_all=session_all, iteration_all = iteration_all, session_from_reco=session_from_reco, 
                     group=group, title=title,
                     description=description, keywords=keywords, genre=genre,
                     date=date, channel=channel, channel_id=channel_id, views=views, 
                     duration=duration, n_occ=n_occ)
  
  # Bind new data
  nodes <- rbind(nodes, line)
  print(line)
}

  #####  Format fields #####
nodes <- nodes %>% 
  mutate(title = gsub('<.*>|[^[:graph:]]',' ',title)) %>% 
  mutate(description = gsub('<.*>|[^[:graph:]]',' ',description))  %>% 
  mutate(channel = gsub('<.*>|[^[:graph:]]',' ',channel))  %>% 
  mutate(views = as.numeric(views))

nodes %>% glimpse

#####  Session lists with unique labels ##### 
for(i in 1:nrow(nodes)){
  sessions <- nodes$session_all[i] %>% str_split(' *; *') %>% unlist %>% unique %>% clean 
  sessions_iter <- nodes$iteration_all[i] %>% str_split(' *; *') %>% unlist %>% unique %>% clean
  nodes$session_n[i] <- sessions %>% length
  nodes$session_all[i] <- sessions %>% paste(collapse=';') 
  nodes$iteration_all[i] <- sessions_iter %>% paste(collapse=";")
  sessions <- nodes$session_direct[i] %>% str_split(' *; *') %>% unlist %>% unique %>% clean 
  nodes$session_direct[i] <- sessions %>% paste(collapse=';') 
  sessions <- nodes$session_from_reco[i] %>% str_split(' *; *') %>% unlist %>% unique %>% clean 
  nodes$session_from_reco[i] <- sessions %>% paste(collapse=';') 
}

nodes %>% glimpse
nodes$session_all %>% unique
nodes$iteration_all %>% unique
nodes$session_direct %>% unique
nodes %>% filter(session_direct=='') %>% glimpse

#####  Check number of nodes #####
# Verify number of nodes/videos is consistent
video_all %>% length
nodes$id %>% unique %>% length
# missing <- video_all[!video_all %in% (nodes$id %>% unique)]
# nodes %>% saveRDS('nodes_backup')
# nodes <-  readRDS('nodes_backup')

#####################################
# MAKE LINKS - LEVEL 1-2
#####################################
#####  Loop through queries #####
# links_backup <- links
# links_l2_backup <- links_l2
links_l2 <- data.frame()
for(k in queries){
  d <- data %>% filter(keyword_ref == k) %>% arrange(iteration)
  
  for(i in 1:nrow(d)){
    tar <- d %>% slice(i)
    if(is.na(tar$video_id)) next
    
    # Direct Links
    if(i != 1){
      src <- d %>% slice(i-1)
      
      if(!is.na(src$video_id)) {
        new_link_id <- paste(src$video_id, tar$video_id)
        
        if(links_l2 %>% filter(link_id==new_link_id & type=='direct') %>% nrow == 0){
          line <- data.frame(source=src$video_id, target=tar$video_id, 
                             session=k, rank=(i-1),
                             session_direct=k, session_all=k, session_n=1, iteration_all=as.character(src$iteration),
                             type='direct', level=1, value=1, n_occ=1,
                             link_id=new_link_id)
          links_l2 <- rbind(links_l2, line)
          print(line)
        } else {
          links_l2 <- links_l2 %>% 
            mutate(session_direct = if_else(
              link_id==new_link_id  & type=='direct', paste0(session_direct,';',k), session_direct)
            ) %>% 
            mutate(session_all = if_else(
              link_id==new_link_id  & type=='direct', paste0(session_all,';',k), session_all)
            ) %>% 
            mutate(n_occ = if_else(link_id==new_link_id & type=='direct', n_occ + 1, n_occ)) %>% 
            mutate(iteration_all = if_else(
              link_id==new_link_id, paste0(iteration_all,';', as.character(src$iteration)), iteration_all )
            )
        }
      }
      # Add session labels to links of all types
      links_l2 <- links_l2 %>% 
        mutate(session_all = if_else(
          link_id==new_link_id, paste0(session_all,';',k), session_all)
        ) %>% 
        mutate(n_occ = if_else(link_id==new_link_id, n_occ + 1, n_occ))%>% 
        mutate(iteration_all = if_else(
          link_id==new_link_id, paste0(iteration_all,';',as.character(src$iteration)), iteration_all)
        ) 
    } 
    
    # Recommendation links
    reco <- tar$reco_videos_id %>% str_split(' *; *') %>% unlist
    reco <- gsub('^.*=','', reco) %>% clean %>% unique 
    
    for(r in reco){
      new_link_id <- paste(tar$video_id, r)
      
      if(links_l2 %>% filter(link_id==new_link_id) %>% nrow == 0){
        line <- data.frame(source=tar$video_id, target=r, 
                           session=k, rank=i, 
                           session_direct=k, session_all=k, session_n=1,  iteration_all=as.character(tar$iteration),
                           type='recommendation', level=2, value=1, n_occ=1,
                           link_id=new_link_id)
        links_l2 <- rbind(links_l2, line)
        print(line)
      } else {
        links_l2 <- links_l2 %>% 
          mutate(session_direct = if_else(
            link_id==new_link_id &  level==2, paste0(session_direct,';',k), session_direct )
          ) %>% 
          mutate(session_all = if_else(
            link_id==new_link_id, paste0(session_all,';',k), session_all )
          ) %>% 
          mutate(n_occ = if_else(link_id==new_link_id, n_occ + 1, n_occ)) %>% 
          mutate(iteration_all = if_else(
            link_id==new_link_id, paste0(iteration_all,';',as.character(tar$iteration)), iteration_all )
          )
      }
    }
  }
}
links_l2 %>% glimpse

#####  Session lists with unique labels ##### 
for(i in 1:nrow(links_l2)){
  sessions <- links_l2$session_all[i] %>% str_split(' *; *') %>% unlist %>% unique %>% clean 
  links_l2$session_n[i] <- sessions %>% length
  links_l2$session_all[i] <- sessions %>% paste(collapse=';') 
  
  sessions <- links_l2$session_direct[i] %>% str_split(' *; *') %>% unlist %>% unique %>% clean 
  links_l2$session_direct[i] <- sessions %>% paste(collapse=';') 
  
  iter <- links_l2$iteration_all[i] %>% str_split(' *; *') %>% unlist %>% unique %>% clean 
  links_l2$iteration_all[i] <- iter %>% paste(collapse=';') 
  
}

links_l2 %>% glimpse
links_l2$session_all %>% unique
links_l2$session_direct %>% unique
links_l2$iteration_all %>% unique
links_l2 %>% filter(session_all=='') %>% glimpse


#####  Check number of nodes ##### 
length(video_all) 
nrow(nodes)
c(links_l2$target, links_l2$source) %>% unique %>% length
nodes$id %>% unique %>% length
nodes$session_from_reco %>% unique %>% glimpse

missing <- nodes$id[nodes$id %>% duplicated]
nodes <- nodes %>% filter(!id %in% missing)

#### experimental 
nodes$iteration_all <- sub("\\;.*", "", nodes$iteration_all) 
#### experimental
links_l2$iteration_all <- sub("\\;.*", "", links_l2$iteration_all) 

#####################################
# WRITE JSON
#####################################
nodes$story <- rep(FALSE,nrow(nodes))
links_l2$story <- rep(FALSE,nrow(links_l2))

nodes <- merge(x = nodes, y = videos, by = "id", all.x = TRUE)

# avaaz 12.05
nodes <- within(nodes, story[id == 'PbEMSXg5z-E' | id == '1zrejG-WI3U' | id == 'jaVL1Ham-4A' | id == 'KazGXAqgkds'] <- TRUE)
links_l2 <- within(links_l2, story[(source == 'PbEMSXg5z-E' & target == '1zrejG-WI3U') | (source == '1zrejG-WI3U' & target == 'jaVL1Ham-4A') | (source == 'jaVL1Ham-4A' & target == 'KazGXAqgkds')] <- TRUE)


json <- list(nodes = nodes, links=links_l2)
json %>% toJSON() %>% write('results_v2_L2_pureSelenium_alltogether.json')

# formatted_data <- read_json('results_v2_L2_pureSelenium.json', simplifyVector=TRUE) %>% glimpse
# formatted_data %>% toJSON()  %>% write('results_v2_L2.json')

# ####################################
# # MAKE LINKS - LEVEL 3-4
# #####################################
# #####  Loop through sessions #####
# direct_video_id <- data$video_id %>% clean %>% unique
# reco_video_id <- data$reco_videos_id %>% str_split(' *; *') %>% unlist %>% clean %>% unique
# links_l4 <- links_l2
# for(k in queries){
#   print(k)
# 
#   d <- data %>% filter(keyword_ref == k)
# 
#   for(i in 1:nrow(d)){
#     src <- d %>% slice(i)
# 
#     # Recommendation links
#     reco <- src$reco_videos_id %>% str_split(' *; *') %>% unlist
#     reco <- gsub('^.*=','', reco) %>% clean %>% unique 
# 
#     ### Next level of recommendation links
#     for(r in reco){
#       reco_l2 <- get_reco(r)
#       reco_l2 <- gsub('^.*=','', reco_l2) %>% clean %>% unique
# 
#       for(r2 in reco_l2){
#         print('L2')
#         print(r2)
# 
#         # Level 3
#         match <- direct_video_id[direct_video_id==r2]
#         print('L3')
#         print(match)
#         
#         for(m in match){
#           new_link_id <- paste(r, r2)
#           
#           if(links_l4 %>% filter(link_id==new_link_id) %>% nrow == 0){
#             line <- data.frame(source=r, target=r2, 
#                                session=k, rank=i,
#                                session_direct=k, session_all=k, session_n=1,
#                                type='recommendation', level=3, value=1, n_occ=1,
#                                link_id=new_link_id)
#             links_l4 <- rbind(links_l4, line)
#             print(line)
#             
#           } else {
#             links_l4 <- links_l4 %>% mutate(session_all = if_else(
#               link_id==new_link_id, paste0(session_all,';',k), session_all
#             )) %>% 
#               mutate(n_occ = if_else(link_id==new_link_id, n_occ + 1, n_occ))
#           }
#         }
# 
#         # Level 4
#         match <- reco_video_id[reco_video_id==r2]
#         print('L4')
#         print(match)
#         for(m in match){
#           new_link_id <- paste(r, r2)
#           
#           if(links_l4 %>% filter(link_id==new_link_id) %>% nrow == 0){
#             line <- data.frame(source=r, target=r2, 
#                                session=k, rank=i,
#                                session_direct=k, session_all=k, session_n=1,
#                                type='recommendation', level=4, value=1, n_occ=1,
#                                link_id=new_link_id)
#             links_l4 <- rbind(links_l4, line)
#             print(line)
#             
#           } else {
#             links_l4 <- links_l4 %>% mutate(session_all = if_else(
#               link_id==new_link_id, paste0(session_all,';',k), session_all
#             )) %>% 
#               mutate(n_occ = if_else(link_id==new_link_id, n_occ + 1, n_occ))
#           }
#         }
#       }
#     }
#   }
# }
# 
# #####  Session lists with unique labels ##### 
# for(i in 1:nrow(links_l4)){
#   sessions <- links_l4$session_all[i] %>% str_split(' *; *') %>% unlist %>% unique %>% clean 
#   links_l4$session_n[i] <- sessions %>% length
#   links_l4$session_all[i] <- sessions %>% paste(collapse=';') 
#   sessions <- links_l4$session_direct[i] %>% str_split(' *; *') %>% unlist %>% unique %>% clean 
#   links_l4$session_direct[i] <- sessions %>% paste(collapse=';') 
# }
# links_l4 %>% glimpse
# links_l4$session_all %>% unique
# links_l4$session_direct %>% unique
# links_l4 %>% filter(session_all=='') %>% glimpse
# 
# #####  Check number of nodes #####
# length(video_all)
# nrow(nodes)
# c(links_l4$target, links_l4$source) %>% unique %>% length
# nodes$id %>% unique %>% length
# 
# links_l4 %>% filter(level>2) %>% glimpse
# 
# #####################################
# # WRITE JSON
# #####################################
# 
# json <- list(nodes = nodes, links=links_l4 %>% filter(level!=4))
# json %>% toJSON() %>% write('results_v2_L3.json')
# 
# json <- list(nodes = nodes, links=links_l4)
# json %>% toJSON() %>% write('results_v2_L4.json')
#

#DONT RUN - BASED ON DIFFERENT DATASETS
# google trends 13.05
nodes <- within(nodes, story[id == '3lrJYTsKdUM' | id == 'GbECT1J9bXg' | id == 't6m49vNjEGs' | id == 'PHe0bXAIuk0'] <- TRUE)
links_l2 <- within(links_l2, story[(source == '3lrJYTsKdUM' & target == 'GbECT1J9bXg') | (source == 'GbECT1J9bXg' & target == 't6m49vNjEGs') | (source == 't6m49vNjEGs' & target == 'PHe0bXAIuk0')] <- TRUE)

#GoogleTrends_17_05_2020_Morn
nodes <- within(nodes, story[id == 'c2fitJMu0aE' | id == 'idYkObkb9C8' | id == 'Fr9L27V337E' | id == '8-_3wOKXzWM'] <- TRUE)
links_l2 <- within(links_l2, story[(source == 'c2fitJMu0aE' & target == 'idYkObkb9C8') | (source == 'idYkObkb9C8' & target == 'Fr9L27V337E') | (source == 'Fr9L27V337E' & target == '8-_3wOKXzWM')] <- TRUE)

#AvaazFreq_15_05_2020
nodes <- within(nodes, story[id == 'BPJJM_hCFj0' | id == '3ojaDMadZXU' | id == 'bka20Q9TN6M' | id == 'yBCAv_NzzPQ'] <- TRUE)
links_l2 <- within(links_l2, story[(source == 'BPJJM_hCFj0' & target == '3ojaDMadZXU') | (source == '3ojaDMadZXU' & target == 'bka20Q9TN6M') | (source == 'bka20Q9TN6M' & target == 'yBCAv_NzzPQ')] <- TRUE)

#TED
nodes <- within(nodes, story[id == '-qsoRkl6Njs' | id == 'GCnRlNK--ws' | id == 'c963NhkfNY0' | id == 'ta154f5Rp5Y'] <- TRUE)
links_l2 <- within(links_l2, story[(source == '-qsoRkl6Njs' & target == 'GCnRlNK--ws') | (source == 'GCnRlNK--ws' & target == 'c963NhkfNY0') | (source == 'c963NhkfNY0' & target == 'ta154f5Rp5Y')] <- TRUE)
