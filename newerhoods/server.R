#
# This is the server logic of a Shiny web application. You can run the
# application by clicking 'Run App' above.
#
# Find out more about building applications with Shiny here:
#
#    http://shiny.rstudio.com/

## Data handling packages
library(dplyr)
library(readxl)
library(broom)
library(stringr)
library(jsonlite)
library(furrr)
library(tictoc)
library(googlesheets)

## UI/UX packages
library(shiny)
library(shinyWidgets)
library(shinyjs)
library(leaflet)
library(htmltools)
library(grDevices)
library(raster)
library(shinyFeedback)
## Spatial packages

## spatial libraries with issues in deployment
# if (!library(gpclib)) install.packages("gpclib", type="source")
# gpclibPermit()

library(rgeos)
library(geojson)
library(rgdal)
library(maptools)
library(sp)
library(spdep)
library(mapview)
library(ggmap)
library(tmap)
library(tmaptools)

## clustering
library(cluster)
library(fpc)
library(ClustGeo)

source("settings_local.R")
source("support_functions.R")

## General settings
options(shiny.maxRequestSize=500*1024^2)
options(future.globals.maxSize= 750*1024^2)
# enableBookmarking(store="url")

# read it back with readRDS
token <- readRDS("sheetstoken.rds")
gs_auth(token=token)
params_file <- gs_key("1YPQdPGVzZX_c9qQn5hnVm5aU_mEd_BqsVrQI8NxcfCc")
saved_params <- gs_read(params_file)

## loading pre-cleaned data
load(file="data/features/processed/pre_compiled_data.RData")
merged_features <- features

saveData <- function(data) {
  # Grab the Google Sheet
  sheet <- gs_key("1YPQdPGVzZX_c9qQn5hnVm5aU_mEd_BqsVrQI8NxcfCc")
  # Add the data as a new row
  sheet %>% gs_add_row(ws="Sheet1", input=data)
}

optimize_params <- TRUE


## Server
function(input, output, session) {
  
  # bookmark_excluded_inputs <- c("upload","geo","lat","lon","boro","ct","boro_ct",
  #                               "user_columns","user_features","share")
  # setBookmarkExclude(names=bookmark_excluded_inputs,session=session)
  # observeEvent(input$share, {
  #   session$doBookmark()
  # })
  
  # onRestore(function(state) {
  #   input_clusters <- state$input$num_clusters
  #   input_enable_heatmap <- state$input$enable_heatmap
  #   input_baseline <- state$input$baseline
  # 
  #   updateSliderInput(session, "num_clusters", value = input_clusters)
  #   updateMaterialSwitch(session, "enable_heatmap", value = input_enable_heatmap)
  #   updateSelectInput(session, "baseline", selected = input_baseline)
  # 
  # })
  
  raw_user_data <- reactive({
    req(input$file)
    if(tolower(tools::file_ext(input$file$datapath)) %in% c("csv", "txt")){
      raw_user_df <- read.csv(input$file$datapath,row.names = NULL)  
    }else if(tolower(tools::file_ext(input$file$datapath)) %in% c("xls","xlsx")){
      raw_user_df <- read_excel(input$file$datapath,row.names = NULL)
      raw_user_df <- as.data.frame(raw_user_df)
    }
    # merged_features <<- features
    # print(basename(input$file$name))
    raw_user_df
  })
  
  output$nrows <- reactive({
    nrow(raw_user_data())
  })
  
  outputOptions(output, "nrows", suspendWhenHidden = FALSE)
  
  ## updating columns to select from
  observe({
    req(input$file)
    col_names <- colnames(raw_user_data())
    
    common_geo_col_names <- c("lat","latitude","lon","longitude",
                              "boro","borocode","borough","boro_code","ct","ct2010","tract","census.tract",
                              "boro_ct2010","boro_ct201","boro_ct")
    common_matches <- match(common_geo_col_names,tolower(col_names))
    
    updateSelectInput(session, "lat", choices= col_names,selected = NULL)
    updateSelectInput(session, "lon", choices= col_names,selected = NULL)
    updateSelectInput(session, "boro", choices= col_names,selected = NULL)
    updateSelectInput(session, "ct", choices= col_names,selected = NULL)
    updateSelectInput(session, "boro_ct", choices= col_names,selected = NULL)
    updateSelectInput(session, "user_columns", choices= col_names,selected = NULL)
    
    if(input$geo == "lat_lon"){
      lat_match <- common_matches[1:2]
      lat_match <- lat_match[!is.na(lat_match)]
      updateSelectInput(session, "lat", selected = ifelse(length(lat_match) >=1,col_names[lat_match[1]],character(0)))
      
      lon_match <- common_matches[3:4]
      lon_match <- lon_match[!is.na(lon_match)]
      updateSelectInput(session, "lon", selected = ifelse(length(lon_match) >=1,col_names[lon_match[1]],character(0)))
      
    }else if(input$geo == "boro_tract"){
      boro_match <- common_matches[5:8]
      boro_match <- boro_match[!is.na(boro_match)]
      updateSelectInput(session, "boro", selected = ifelse(length(boro_match) >=1,col_names[boro_match[1]],character(0)))
      
      tract_match <- common_matches[9:12]
      tract_match <- tract_match[!is.na(tract_match)]
      updateSelectInput(session, "ct", selected = ifelse(length(tract_match) >=1,col_names[tract_match[1]],character(0)))
      
    }else if(input$geo == "boro_ct"){
      boro_ct_match <- common_matches[13:15]
      boro_ct_match <- boro_ct_match[!is.na(boro_ct_match)]
      updateSelectInput(session, "boro_ct", selected = ifelse(length(boro_ct_match) >=1,col_names[boro_ct_match[1]],character(0)))
    }
  })
  
  observeEvent({input$lat 
    input$lon 
    input$boro 
    input$ct
    input$boro_ct},{
      col_names <- colnames(raw_user_data())
      geo_cols <- c(input$lat, input$lon, input$boro, input$ct, input$boro_ct)
      geo_cols <- geo_cols[!is.na(geo_cols)]
      feature_cols <- col_names[!(col_names %in% geo_cols)]
      col_types <- sapply(raw_user_data(), class)
      numeric_cols <- col_names[col_types %in% c("integer","numeric")]
      feature_cols <- feature_cols[feature_cols %in% numeric_cols]
      updateSelectInput(session, "user_columns", choices= feature_cols,selected = NULL)
    })
  
  user_data <- observeEvent(input$upload_done,{
    saved_params <- gs_read(params_file)
    req(input$file)
    # toggleModal(session,modalId = "modal_upload",toggle="close")
    # removeModal(session,modalId = "modal_upload")
    if(input$geo == 'lat_lon'){
      req(input$lat,input$lon)
      ## convert points to rates fatures
      
      user_df <- point_data_to_feature_columns(raw_user_data(),lat=input$lat,
                                               lon=input$lon,cols=input$user_columns) 
      
      colnames(user_df) <- paste0("USER_",colnames(user_df))
      colnames(user_df)[1] <- "boro_ct201"
    }else if(input$geo == 'boro_tract'){
      req(input$boro,input$ct,input$user_columns)
      ## reformat the boro and tract columns and combine for merging
      user_df <- raw_user_data()
      padded_tract_id <- str_pad(user_df[,input$ct],5,side="right",pad="0")
      user_df$boro_ct201 <- paste0(user_df[,input$boro],str_pad(padded_tract_id,6,side="left",pad="0"))
      user_df <- user_df %>% group_by(boro_ct201) %>% 
        dplyr::select(input$user_columns) %>%
        summarise_all(funs(mean))
      user_df <- as.data.frame(user_df)
      colnames(user_df) <- c("boro_ct201",paste0("USER_",input$user_columns))
      user_df$boro_ct201 <- as.character(user_df$boro_ct201)
    }else{
      req(input$boro_ct,input$user_columns)
      ## reformat the combined boro-tract column
      user_df <- raw_user_data()
      user_df$boro_ct201 <- as.character(user_df[,input$boro_ct])
      user_df <- user_df %>% dplyr::select(input$user_columns,boro_ct201) %>% 
        group_by(boro_ct201) %>% 
        summarise_all(funs(mean))
      user_df <- as.data.frame(user_df)
      colnames(user_df) <- c("boro_ct201",paste0("USER_",input$user_columns))
      user_df$boro_ct201 <- as.character(user_df$boro_ct201)
    }
    # print(colnames(user_df))
    generated_feature_names <- gsub("USER_","",colnames(user_df))
    generated_feature_names <- generated_feature_names[generated_feature_names != "boro_ct201"]
    pretty_names <- get_pretty_names(generated_feature_names,type="checkbox")
    
    # updateSelectInput(session, "user_features", choices= generated_feature_names)
    updateCheckboxGroupInput(session, "user_features", choiceValues=generated_feature_names,
                             choiceNames = pretty_names)
    merged_features <<- left_join(features,user_df,by="boro_ct201")
    merged_features[is.na(merged_features)] <<- 0
    return(user_df)
  })
  
  
  user_selection <- eventReactive(input$select,{
    ## Send message to show spinner
    
    session$sendCustomMessage("spinner-on", "True")
    
    inputs <- paste0("c(",paste(feature_inputs$input_ids,collapse = ","),")")
    selection <- eval(parse(text=inputs))
    # c(input$crime_features,input$housing,input$call_features)
    
    ## additional conditions
    if("sale_price" %in% selection){
      selection <- selection[selection != "sale_price"]  
      selection <- c(selection,input$sales_features)
    }
    selection <- paste0(selection,collapse = "|")
    
    user_feature_selection <- paste0("USER_",input$user_features,collapse = "|")
    
    if(user_feature_selection != "USER_"){
      selection <- paste0(c(selection,user_feature_selection),collapse = "|")  
      selection <- gsub("^\\|","",selection)
    }
    
    selection
  }, ignoreNULL = FALSE) # change to false to load initial state
  
  
  
  # observeEvent(input$select,{
  #   ## To change
  #   if((is.null(input$crime_features) & is.null(input$housing) & 
  #       is.null(input$call_features) & is.null(input$user_features))){
  #     showSnackbar("FeatureSelection")  
  #   }  
  # })
  # 
  
  dist_mat <- eventReactive(user_selection(),{
    features_to_use <- grepl(user_selection(),colnames(merged_features))
    feature_set <- unlist(strsplit(user_selection(),"\\|"))
    
    ### Clustering the data based on selected features
    D0 <- dist(scale(merged_features[,features_to_use]))
    
    return(D0)
  },ignoreNULL = FALSE)
  

  optimized_params <- reactive({
    if(sum(user_selection() %in% saved_params$features)*1L > 0){
      opt_params <- saved_params[saved_params$features == user_selection(),]
    }else{
      if(optimize_params){
        ##
        D0 <- dist_mat()/max(dist_mat())
        D1 <- D1/max(D1)
        
        #### Finding optimal parameters
        # plan(multisession) ## using 4 processors
        plan(multiprocess(workers=4)) ## using 4 processors
        tic()
        
        range_k <-seq(5,200,by=1)
        res <- hclust(D0, method = "ward.D")
        avg_sil <- range_k %>% future_map_dbl(get_sil_width,D0,res)
        
        cl_metric <- data.frame(k=range_k,avg_sil=avg_sil)
        cl_metric$groups <- cut(range_k,breaks=c(4,50,100,150,200))
        s <- cl_metric %>% group_by(groups) %>% summarize(K=max(k),k_opt=k[which.max(avg_sil)])
        
        opt_k <- s$k_opt
        # print(opt_k)
        
        # toc()
        
        # plan(multiprocess(workers=4)) ## using 4 processors
        # tic()
        range_alpha <- c(0,seq(0.1,0.5,by=0.05),1)
        
        grid_search <- expand.grid(k=opt_k,alpha=range_alpha)
        
        D0_sq <- as.matrix((D0))^2
        D1_sq <- as.matrix((D1))^2
        n <- dim(D0_sq)[1]
        T0 <- (sum(D0_sq)/(2*n^2))
        T1 <- (sum(D1_sq)/(2*n^2))
        
        cl_stat <- grid_search %>% future_pmap(.f=get_homogeneity,D0=D0,D1=D1,D0_sq=D0_sq,
                                               D1_sq=D1_sq,T0=T0,T1=T1)
        
        rm("D0_sq","D1_sq","T0","T1") ## removing large objects
        
        grid_search <- cbind(grid_search,data.frame(matrix(unlist(cl_stat),ncol=2,byrow=TRUE)))
        colnames(grid_search)[3:4] <- c("Q0","Q1")
        
        # print(grid_search)
        
        opt_params <- grid_search %>% group_by(k) %>% 
          mutate(Q0norm=Q0/max(Q0),Q1norm=Q1/max(Q1)) %>%
          mutate(Q0gain=(Q0norm-lag(Q0norm,1))/Q0,Q1gain=(Q1norm-lag(Q1norm,1))/Q1) %>%
          mutate(tot_gain=(Q0gain+Q1gain)) %>%
          filter(alpha > 0, alpha < 1) %>%
          group_by(k) %>%
          mutate(opt_alpha=get_opt(alpha,tot_gain)) %>%
          summarise(alpha=mean(opt_alpha))
        toc()
        
        opt_params$features <- user_selection()
        saved_params <- rbind(saved_params,opt_params)
        
        if(!grepl("USER_",user_selection())){
          saveData(opt_params)  
        }
        
        # print(saved_params)
        # save(saved_params,file="data/saved_params.RData")
        
        
      }else{
        opt_params <- data.frame(alpha=rep(0.2,4),k=c(50,100,150,200))
      }
      
    }
    opt_params <- opt_params[order(opt_params$k),]
    clus_buttons <- c("clus_rec_1","clus_rec_2","clus_rec_3","clus_rec_4")
    
    for(i in c(1:4)){
      updateActionButton(session,inputId = clus_buttons[i],label = opt_params$k[i])
    }
    # print(opt_params)
    return(opt_params)
  })
  
  observeEvent({input$clus_rec_1},
               {op <- optimized_params()
               updateSliderInput(session,"num_clusters",value=op$k[1])})
  
  observeEvent({input$clus_rec_2},
               {op <- optimized_params()
               updateSliderInput(session,"num_clusters",value=op$k[2])})
  
  observeEvent({input$clus_rec_3},
               {op <- optimized_params()
               updateSliderInput(session,"num_clusters",value=op$k[3])})
  
  observeEvent({input$clus_rec_4},
               {op <- optimized_params()
               updateSliderInput(session,"num_clusters",value=op$k[4])})
  
  alpha_for_k <- reactive({
    op <- optimized_params()
    opt_alpha <- op$alpha[which.min(abs(input$num_clusters - op$k))]
    return(opt_alpha)
  })
  
  tree <- reactive({
    
    set.seed(1729)
    tree <- hclustgeo(dist_mat(),D1,alpha=alpha_for_k())
    
    return(tree)
  })
  
  clus_res <- reactive({
    ### Subset data based on user selection of features
    features_to_use <- grepl(user_selection(),colnames(merged_features))
    feature_set <- unlist(strsplit(user_selection(),"\\|"))
    
    K <- input$num_clusters
    clusters <- data.frame(cl=cutree(tree(),K))
    
    ## cluster statistics to find optimal numbers
    # avg_sil <- rep(NA,200)
    # for(i in c(5:200)){
    #   c <- cutree(tree(),i) 
    #   avg_sil[i] <- summary(silhouette(c,D))$avg.width
    # }
    # cl_metric <- data.frame(k=c(1:200),avg_sil=avg_sil)
    # cl_metric$groups <- cut(c(1:200),breaks=4)
    # 
    # s <- cl_metric %>% group_by(groups) %>% summarize(K=max(k),k_opt=min(k)+which.max(avg_sil)-1)
    # 
    
    ## generating cluster average statistics (weighted mean for rates)
    ## Calculating total population and number of tracts for each cluster
    cluster_vals <- cbind(clusters,merged_features[,feature_set],merged_features$pop_2010)
    colnames(cluster_vals) <- c("cl",feature_set,"pop_2010")
    cluster_pop <- cluster_vals %>% group_by(cl) %>% summarise(pop = sum(pop_2010),n = n())
    
    ## Going from rates back to total cases to make cluster aggregation easier
    feature_info <- process_features_json()
    rate_features <- feature_info$column_name[feature_info$is_rate]
    rate_features <- rate_features[rate_features %in% feature_set]
    user_rate_features <- feature_set[grepl("USER",feature_set)]
    user_rate_features <- user_rate_features[grepl("rate",user_rate_features)]
    rate_features <- c(rate_features,user_rate_features)
    
    if(length(rate_features) > 0){
      cluster_vals[,rate_features] <- cluster_vals[,rate_features]*cluster_vals$pop_2010/1000
    }
    
    ## Summarising over each cluster and calculating mean statistics
    cluster_vals <- cluster_vals %>% group_by(cl) %>% summarise_if(is.numeric,mean)
    colnames(cluster_vals) <- c("cl",paste0(c(feature_set,"pop"),"_mean"))
    cluster_vals <- left_join(cluster_vals,cluster_pop,by="cl")
    
    ## for rate variables, dividing over the cluster population to get an overall average
    if(sum(grepl("rate",feature_set)) > 0){
      cluster_vals[,grepl("rate",colnames(cluster_vals))] <- cluster_vals[,grepl("rate",colnames(cluster_vals))]*cluster_vals$n*1000/cluster_vals$pop
    }
    
    cluster_vals <- cluster_vals[,c("cl",paste0(feature_set,"_mean"))]
    
    
    
    ## distance between clusters to use for heatmap
    cluster_vals$dist <- eucd_dist(cluster_vals)
    
    ## merging with cluster results
    clusters <- left_join(clusters,cluster_vals,by="cl")
    clusters$boro_ct201 <- as.character(merged_features$boro_ct201)
    clusters <- left_join(data.frame(boro_ct201=census_tracts$boro_ct201,
                                     stringsAsFactors = FALSE),
                          clusters,by="boro_ct201")
    
    ## adding to census tracts to merge polygons
    census_tracts@data$cl <- clusters$cl
    census_tracts <- census_tracts[order(census_tracts$boro_ct201),]
    
    ## merged polygon
    newerhoods <- unionSpatialPolygons(census_tracts,census_tracts$cl)
    
    ## adding cluster data
    census_df <- as(census_tracts,"data.frame")
    newerhoods_df <- clusters %>% group_by(cl) %>% summarise_if(is.numeric,mean)
    newerhoods_df <- as.data.frame(newerhoods_df)
    newerhoods_df <- newerhoods_df[!is.na(newerhoods_df$cl),]
    newerhoods_df$labels <-  get_labels(newerhoods_df)
    
    newerhoods <- SpatialPolygonsDataFrame(newerhoods,newerhoods_df)
    
    return(list(clusters,newerhoods))
  }) %>% debounce(10)
  
  newerhoods <- reactive({
    
    enable_heatmap <- input$enable_heatmap
    
    newerhoods <- clus_res()[[2]]
    
    if(enable_heatmap==TRUE){
      heatmap_palette <- c('#ffffb2','#fed976','#feb24c',
                           '#fd8d3c','#fc4e2a','#e31a1c','#b10026')
      probs <- seq(from=0,to=1,length.out = length(heatmap_palette))
      bins <- quantile(newerhoods$dist, probs, na.rm = TRUE, names = FALSE)
      bins <- bins + seq_along(bins) * .Machine$double.eps
      bins[1] <- min(newerhoods$dist)
      pal_heatmap <-  colorBin(heatmap_palette, domain = NULL, bins = bins, na.color = "#A9A9A9")
      
      # colorQuantile(heatmap_palette,newerhoods$dist,
      #                            n=length(heatmap_palette),
      #                            na.color = "#A9A9A9A9")
      newerhoods$colour <- pal_heatmap(newerhoods$dist)
      
      # output$heatmap_palette <- heatmap_palette
    }else{
      map_cols <- c('#b7e882','#f4f062','#8fe2b4',
                    '#237de0','#8dcd5c','#a327ad',
                    '#d30000','#f9158d','#44b244',
                    '#0093ee','#136bb0','#1d4c7b',
                    '#1d293a','#017f7c','#015d5f','#003b3e')
      
      newerhoods$colour  <- map_coloring(newerhoods, palette=map_cols)
      # pal <- colorNumeric(map_cols,
      #                     c(0:(length(map_cols)-1)),
      #                     na.color = "#A9A9A9A9")
      # newerhoods$colour <- pal(newerhoods$cl%%length(map_cols))
    }
    
    return(newerhoods)
  })
  
  # outputOptions(output, "heatmap_palette", suspendWhenHidden = FALSE)
  
  ##### Interactive Map #####
  map_reactive <- reactive({
    
    leaflet() %>%
      setView(-74.02,40.72,11) %>%
      # addProviderTiles("MapBox", options = providerTileOptions(
      #   id= "mapbox.light",
      #   accessToken = Sys.getenv('MAPBOX_ACCESS_TOKEN'))
      # ) %>%
      addProviderTiles("CartoDB.Positron") %>%
      addMapPane("newerhoods", zIndex = 410) %>%
      addPolygons(data=newerhoods(),
                  fillColor = newerhoods()$colour,
                  stroke = TRUE,
                  weight = 1,
                  opacity = 0.5,
                  color = "lightgrey",
                  fillOpacity = 0.6,
                  ## highights
                  highlight = highlightOptions(
                    weight = 4,
                    color = ifelse(input$enable_heatmap == FALSE,"orange","green"),
                    opacity = 0.8,
                    fillOpacity = 0.6,
                    bringToFront = F),
                  ## labels
                  label = newerhoods()$labels %>% lapply(HTML),
                  labelOptions = labelOptions(
                    style = list("font-weight"="normal",
                                 padding = "3px 8px"),
                    textsize = "15px",
                    direction = "auto"),
                  options = pathOptions(pane = "newerhoods")
      )
  })
  
  output$map <- renderLeaflet({
    map_reactive()
  })
  
  ## To do: Simplify this. Feels like too many observes
  ## Adding Heatmap Legend
  ## function to add legend to plot
  ## function to add legend to plot
  add_legend <- function(enable_heatmap){
    proxy <- leafletProxy("map")
    # heatmap_palette <- c('#0093ee','#136bb0','#1d4c7b','#017f7c','#015d5f','#003b3e', '#1d293a')
    # heatmap_palette <- output$heatmap_palette
    heatmap_palette <- c('#ffffb2','#fed976','#feb24c',
                         '#fd8d3c','#fc4e2a','#e31a1c','#b10026')
    if(enable_heatmap == TRUE){
      proxy %>% addLegend(position="bottomright",
                          colors = heatmap_palette[length(heatmap_palette):1],
                          labels = c("Low",rep("",(length(heatmap_palette)-2)),"High")[length(heatmap_palette):1],
                          opacity = 1)
    }else{
      proxy %>% clearControls()}
  }
  
  observe({add_legend(input$enable_heatmap)
    # shinyjs::hideElement(id = 'loading')
    })
  observeEvent(clus_res(),{add_legend(input$enable_heatmap)
    # shinyjs::hideElement(id = 'loading')
    })
  
  
  ### Baseline Map
  
  ## load baseline maps
  # load_baseline_maps()
  source_folder <- "data/boundaries/processed/"
  files <- list.files(source_folder,"*.rds")
  for(i in c(1:length(files))){
    tmp <- readRDS(file=paste0(source_folder,files[i]))
    assign(gsub(".rds","",files[i]),tmp)
  }
  
  # baselines <- c("cds","ntas","pumas","precincts","school_dists")
  baselines <- as.vector(unlist(get_baseline_choices()))[-1] ## "none" is always the first. excluding that
  # gsub(".rds","",files)
  
  add_baselines <- function(){
    for(i in c(1:length(baselines))){
      baseline_map <- get(baselines[i])
      # readRDS(file=paste0(source_folder,files[i]))
      proxy <- leafletProxy("map")
      proxy %>%
        addMapPane("baseline", zIndex = 420) %>%
        addPolylines(data=baseline_map,
                     stroke=TRUE,
                     weight=2,
                     opacity=0.75,
                     color="white",
                     dashArray="5",
                     group = baselines[i],
                     options = pathOptions(pane = "baseline"))
      if(baselines[i] != input$baseline){
        proxy %>% hideGroup(baselines[i])
      }
    }
  }
  
  observeEvent({input$enable_heatmap},{add_baselines()
    session$sendCustomMessage("spinner-off", "True")})
  observeEvent({clus_res()},{add_baselines()
    session$sendCustomMessage("spinner-off", "True")})
  
  overlap <- reactive({
    if(input$baseline != "none"){
      baseline_map <- get(input$baseline)
      # jaccard_insights <- get_jaccard_index(newerhoods(),baseline_map,j_threshold = 0.748)
      # baseline_highlight_areas <- jaccard_insights$highlight_area
      # baseline_highlight_hatch <- jaccard_insights$hatch
      # jaccard_index <- 100*round(jaccard_insights$jaccard_index,4)
      
      proxy <- leafletProxy("map")
      proxy %>% 
        addMapPane("highlight_lines", zIndex = 430) %>%
        # addMapPane("highlight", zIndex = 390) %>%
        # addPolygons(data=baseline_highlight_areas,
        #             fillColor = "black",
        #             fillOpacity = 0,
        #             stroke=TRUE,
        #             weight=2,
        #             opacity=0.75,
        #             color="orange",
        #             options = pathOptions(pane = "highlight")) %>%
        addPolylines(data=baseline_highlight_hatch,
                     color=ifelse(input$enable_heatmap,"grey","#f58131"),
                     weight=2,
                     opacity = 0.8,
                     options = pathOptions(pane = "highlight_lines"))
      
      
      # print(round(jaccard_index,2))
    }
    # else{
    #   jaccard_index <- ""
    # }
    # return(jaccard_index)
  })
  
  output$overlap <- renderText({
    if(overlap() != ""){
      paste0("Overlap: ",overlap(),"%")  
    }else{
      overlap()
    }
  })
  
  observeEvent(input$baseline,{
    if(input$baseline != "none"){
      baseline_map <- get(input$baseline)
      
      proxy <- leafletProxy("map")
      proxy %>% hideGroup(baselines)
      proxy %>% showGroup(input$baseline)
    }else{
      proxy <- leafletProxy("map")
      proxy %>% hideGroup(baselines)
    }
  })
  
  ## Add the ability to download the results as a csv
  output$downloadCSV<- downloadHandler(
    filename = function() {
      paste("newerhoods",".csv",sep="")
    },
    content = function(file){
      ## prettifying csv before download
      cluster_results <- clus_res()[[1]]
      cluster_results <- cluster_results[,-which(names(cluster_results) == "dist")]
      colnames(cluster_results)[which(colnames(cluster_results)=="cl")] <- "cluster_id" 
      colnames(cluster_results)[which(colnames(cluster_results)=="boro_ct201")] <- "boro_tract_2010" 
      
      write.csv(cluster_results, file, row.names = FALSE)
    }
  )
  
  
  ## Add the ability to download the results as GeoJSON
  output$downloadGEOJson<- downloadHandler(
    filename = function() {
      paste("newerhoods",".geojson",sep="")
    },
    content = function(file){
      write(as.geojson(clus_res()[[2]]), file )
    }
  )
  
  ## Add the ability to download the results as a PNG
  output$downloadPNG<- downloadHandler(
    filename = function() {
      paste("newerhoods",".png",sep="")
    },
    content = function(file){
      nh <- newerhoods()
      bbox <- nh@bbox
      map_dl <- get_stamenmap(bbox = c(left=bbox[1,1], bottom=bbox[2,1],
                                       right=bbox[1,2],top=bbox[2,2]),
                              maptype = "toner-lite", source = "stamen", zoom = 11)
      
      tt <- tidy(nh,region = "cl")
      tt <- as.data.frame(tt, stringsAsFactors = FALSE)
      
      p <- ggmap(map_dl)
      
      p <- p +
        geom_polygon(data = fortify(tt),
                     aes(long, lat, group = group, fill=id),
                     alpha = 0.6, size = 0) +
        scale_fill_manual(values=nh$colour) +
        theme(legend.position="none")
      
      if(input$baseline != "none"){
        bl_sp <- get(input$baseline)
        # Coerce the baseline spatial df into a regular df suitable for geom_polygon
        # TODO get rid of "binding character and factor vector, coercing into character vector" warnings
        bl_sp@data$id <- rownames(bl_sp@data)
        bl_df <- tidy(bl_sp, region = "id")
        bl_df <- as.data.frame(bl_df, stringsAsFactors = FALSE)
        p <- p +
          geom_polygon(data = bl_df, 
                       aes(long, lat, group = group, fill = NA), 
                       colour = "white", linetype = "dashed", size = 0.5)
      }
      
      ggsave(file, plot = p, device = "png")
    }
  )
  
}


