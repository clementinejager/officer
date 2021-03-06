#' @export
#' @title open a connexion to a 'PowerPoint' file
#' @description read and import a pptx file as an R object
#' representing the document.
#' @param path path to the pptx file to use as base document.
#' @param x an rpptx object
#' @examples
#' read_pptx()
#' @importFrom xml2 read_xml xml_length xml_find_first xml_attr xml_ns
read_pptx <- function( path = NULL ){

  if( !is.null(path) && !file.exists(path))
    stop("could not find file ", shQuote(path), call. = FALSE)

  if( is.null(path) )
    path <- system.file(package = "officer", "template/template.pptx")

  package_dir <- tempfile()
  unpack_folder( file = path, folder = package_dir )

  obj <- list(package_dir = package_dir)


  obj$table_styles <- read_table_style(package_dir)

  obj$presentation <- presentation$new(package_dir)

  obj$masterLayouts <- dir_master$new(package_dir, slide_master$new("ppt/slideMasters") )

  obj$slideLayouts <- dir_layout$new( package_dir,
                                      master_metadata = obj$masterLayouts$get_metadata(),
                                      master_xfrm = obj$masterLayouts$xfrm() )

  obj$slide <- dir_slide$new( package_dir, obj$slideLayouts$get_xfrm_data() )
  obj$content_type <- content_type$new( package_dir )
  obj$core_properties <- read_core_properties(package_dir)

  obj$cursor = obj$slide$length()
  class(obj) <- "rpptx"
  obj
}

read_table_style <- function(path){
  file <- file.path(path, "ppt/tableStyles.xml")
  if (!file.exists(file)) {
    warning("tableStyles.xml file does not exist in PPTX")
    return(NULL)
  }
  doc <- read_xml(file)
  nodes <- xml_find_all(doc, "//a:tblStyleLst")
  data.frame(def = xml_attr(nodes, "def"),
             styleName = xml_attr(nodes, "styleName"),
             stringsAsFactors = FALSE )
}

#' @export
#' @param target path to the pptx file to write
#' @param ... unused
#' @rdname read_pptx
#' @examples
#' # write a rdocx object in a docx file ----
#' if( require(magrittr) ){
#'   file <- tempfile(fileext = ".pptx")
#'   read_pptx() %>% print(target = file)
#'   # full path of produced file is returned
#'   print(.Last.value)
#' }
print.rpptx <- function(x, target = NULL, ...){

  if( is.null( target) ){
    cat("pptx document with", length(x), "slide(s)\n")
    cat("Available layouts and their associated master(s) are:\n")
    print(as.data.frame( layout_summary(x)) )
    return(invisible())
  }

  if( !grepl(x = target, pattern = "\\.(pptx)$", ignore.case = TRUE) )
    stop(target , " should have '.pptx' extension.")

  x$presentation$save()
  x$content_type$save()

  x$slide$save_slides()

  x$core_properties['modified','value'] <- format( Sys.time(), "%Y-%m-%dT%H:%M:%SZ")
  x$core_properties['lastModifiedBy','value'] <- Sys.getenv("USER")
  write_core_properties(x$core_properties, x$package_dir)

  pack_folder(folder = x$package_dir, target = target )
}




#' @export
#' @importFrom xml2 xml_name<- xml_set_attrs xml_ns xml_remove
#' @title add a slide
#' @description add a slide into a pptx presentation
#' @param x rpptx object
#' @param layout slide layout name to use
#' @param master master layout name where \code{layout} is located
#' @examples
#' my_pres <- read_pptx()
#' my_pres <- add_slide(my_pres,
#'   layout = "Two Content", master = "Office Theme")
add_slide <- function( x, layout, master ){

  slide_info <- x$slideLayouts$get_metadata()
  slide_info <- slide_info[slide_info$name == layout & slide_info$master_name == master, ]

  if( nrow( slide_info ) < 1 )
    stop("could not find layout named ", shQuote(layout), " in master named ", shQuote(master))
  new_slidename <- x$slide$get_new_slidename()

  xml_file <- file.path(x$package_dir, "ppt/slides", new_slidename)
  xml_layout <- file.path(x$package_dir, "ppt/slideLayouts", slide_info$filename)
  layout_obj <- x$slideLayouts$collection_get(slide_info$filename)
  layout_obj$write_template(xml_file)

  # update presentation elements
  x$presentation$add_slide(target = file.path( "slides", new_slidename) )
  x$content_type$add_slide(partname = file.path( "/ppt/slides", new_slidename) )

  x$slide$add_slide(xml_file, x$slideLayouts$get_xfrm_data() )

  x$cursor = x$slide$length()
  x

}

#' @export
#' @rdname read_pptx
#' @section number of slides:
#' Function \code{length} will return the number of slides.
length.rpptx <- function( x ){
  x$slide$length()
}

#' @export
#' @rdname read_pptx
#' @section slides width and height:
#' Function \code{slide_size} will return the size of slides.
#' @importFrom xml2 xml_attrs xml_find_first
slide_size <- function(x) {
  pres <- x$presentation$get()
  dimensions <- xml_attrs(xml_find_first(pres, "p:sldSz"))
  dimensions <- as.list(as.integer(dimensions[c("cx", "cy")]) / 914400)
  names(dimensions) <- c("width", "height")
  dimensions
}


#' @export
#' @title change current slide
#' @description change current slide index of an rpptx object.
#' @param x rpptx object
#' @param index slide index
#' @examples
#' doc <- read_pptx()
#' doc <- add_slide(doc, layout = "Title and Content", master = "Office Theme")
#' doc <- add_slide(doc, layout = "Title and Content", master = "Office Theme")
#' doc <- add_slide(doc, layout = "Title and Content", master = "Office Theme")
#' doc <- on_slide( doc, index = 1)
#' doc <- ph_with_text(x = doc, type = "title", str = "First title")
#' doc <- on_slide( doc, index = 3)
#' doc <- ph_with_text(x = doc, type = "title", str = "Third title")
#'
#' file <- tempfile(fileext = ".pptx")
#' print(doc, target = file )
on_slide <- function( x, index ){

  l_ <- length(x)
  if( l_ < 1 ){
    stop("presentation contains no slide", call. = FALSE)
  }
  if( !between(index, 1, l_ ) ){
    stop("unvalid index ", index, " (", l_," slide(s))", call. = FALSE)
  }

  filename <- basename( x$presentation$slide_data()$target[index])
  location <- which( x$slide$get_metadata()$name %in% filename )

  x$cursor <- x$slide$slide_index(filename)

  x
}

#' @export
#' @title move a slide
#' @description move a slide in a pptx presentation
#' @param x rpptx object
#' @param index slide index, default to current slide position.
#' @param to new slide index.
#' @note cursor is set on the last slide.
#' @examples
#' x <- read_pptx()
#' x <- add_slide(x, layout = "Title and Content",
#'   master = "Office Theme")
#' x <- ph_with_text(x, type = "body", str = "Hello world 1")
#' x <- add_slide(x, layout = "Title and Content",
#'   master = "Office Theme")
#' x <- ph_with_text(x, type = "body", str = "Hello world 2")
#' x <- move_slide(x, index = 1, to = 2)
move_slide <- function( x, index, to ){

  x$presentation$slide_data()

  if( is.null(index) )
    index <- x$cursor

  l_ <- length(x)

  if( l_ < 1 ){
    stop("presentation contains no slide", call. = FALSE)
  }
  if( !between(index, 1, l_ ) ){
    stop("unvalid index ", index, " (", l_," slide(s))", call. = FALSE)
  }
  if( !between(to, 1, l_ ) ){
    stop("unvalid 'to' ", to, " (", l_," slide(s))", call. = FALSE)
  }

  x$presentation$move_slide(from = index, to = to)
  x$cursor <- to
  x
}



#' @export
#' @title remove a slide
#' @description remove a slide from a pptx presentation
#' @param x rpptx object
#' @param index slide index, default to current slide position.
#' @note cursor is set on the last slide.
#' @examples
#' my_pres <- read_pptx()
#' my_pres <- add_slide(my_pres,
#'   layout = "Two Content", master = "Office Theme")
#'
#' my_pres <- remove_slide(my_pres)
remove_slide <- function( x, index = NULL ){

  l_ <- length(x)
  if( l_ < 1 ){
    stop("presentation contains no slide to delete", call. = FALSE)
  }

  if( is.null(index) )
    index <- x$cursor

  if( !between(index, 1, l_ ) ){
    stop("unvalid index ", index, " (", l_," slide(s))", call. = FALSE)
  }
  filename <- basename( x$presentation$slide_data()$target[index])
  location <- which( x$slide$get_metadata()$name %in% filename )

  del_file <- x$slide$remove_slide(location)

  # update presentation elements
  x$presentation$remove_slide(del_file)
  x$content_type$remove_slide(partname = del_file )
  x$cursor = x$slide$length()
  x

}

#' @export
#' @title presentation layouts summary
#' @description get informations about slide layouts and
#' master layouts into a data.frame.
#' @param x rpptx object
#' @examples
#' my_pres <- read_pptx()
#' layout_summary ( x = my_pres )
layout_summary <- function( x ){
  data <- x$slideLayouts$get_metadata()
  data.frame(layout = data$name, master = data$master_name, stringsAsFactors = FALSE)
}

#' @export
#' @title slide layout properties
#' @description get information about a particular slide layout
#' into a data.frame.
#' @param x rpptx object
#' @param layout slide layout name to use
#' @param master master layout name where \code{layout} is located
#' @examples
#' x <- read_pptx()
#' layout_properties ( x = x, layout = "Title Slide", master = "Office Theme" )
#' layout_properties ( x = x, master = "Office Theme" )
#' layout_properties ( x = x, layout = "Two Content" )
#' layout_properties ( x = x )
layout_properties <- function( x, layout = NULL, master = NULL ){

  data <- x$slideLayouts$get_xfrm_data()

  if( !is.null(layout) && !is.null(master) ){
    data <- data[data$name == layout & data$master_name == master,]
  } else if( is.null(layout) && !is.null(master) ){
    data <- data[data$master_name == master,]
  } else if( !is.null(layout) && is.null(master) ){
    data <- data[data$name == layout,]
  }
  data <- data[,c("master_name", "name", "type", "id", "ph_label", "ph", "offx", "offy", "cx", "cy")]
  data[["offx"]] <- data[["offx"]] / 914400
  data[["offy"]] <- data[["offy"]] / 914400
  data[["cx"]] <- data[["cx"]] / 914400
  data[["cy"]] <- data[["cy"]] / 914400

  data
}

#' @export
#' @title PowerPoint placeholder parameters annotation
#' @description generates a slide from each layout in the base document to
#' identify the placeholder indexes, types, names, master names and layout names.
#'
#' This is to be used when need to know what parameters should be used with
#' \code{ph_location*} calls. The parameters are printed in their corresponding shapes.
#'
#' Note that if there are duplicated \code{ph_label}, you should not use \code{ph_location_label}.
#'
#' @param path path to the pptx file to use as base document or NULL to use the officer default
#' @param output_file filename to store the annotated powerpoint file or NULL to suppress generation
#' @return x rpptx object of the annotated PowerPoint file
#' @examples
#' # To generate an anotation of the default base document with officer:
#' annotate_base(output_file = tempfile(fileext = ".pptx"))
#'
#' # To generate an annotation of the base document 'mydoc.pptx' and place the
#' # annotated output in 'mydoc_annotate.pptx'
#' # annotate_base(path = 'mydoc.pptx', output_file='mydoc_annotate.pptx')
#'
annotate_base <- function(path = NULL, output_file = 'annotated_layout.pptx' ){

  ppt <- read_pptx(path=path)

  # Pulling out all of the layouts stored in the template
  lay_sum <- layout_summary(ppt)

  # Looping through each layout

  for(lidx in seq_len(nrow(lay_sum))){
    # Pulling out the layout properties

    layout <- lay_sum[lidx, 1]
    master <- lay_sum[lidx, 2]
    lp <- layout_properties ( x = ppt, layout = layout, master = master)
    lp <- lp[order(lp$type, as.integer(lp$id)),]

    id <- unlist( lapply(rle( lp$type)$lengths, function(x){
      seq_len(x)
    }) )
    textstr <- sprintf('type="%s", index =%d, ph_label="%s"',
                       lp$type, id, lp$ph_label)

    # Adding a slide for the current layout
    ppt <- add_slide(x=ppt, layout = layout, master = master)
    size <- slide_size(ppt)
    ppt <- ph_empty(x=ppt,
                   location = ph_location(left = 0, top = -0.5, width = size$width, height = 1,
                                          bg = "transparent", label = "layout_ph") )
    fpar_ <- fpar(sprintf('layout ="%s", master = "%s"', layout, master),
                  fp_t = fp_text(color = "orange", font.size = 20),
                  fp_p = fp_par(text.align = "right", padding = 5)
                  )
    ppt <- ph_add_fpar(x = ppt, value = fpar_, ph_label = "layout_ph", par_default = FALSE)


    # Blank slides have nothing
    if(length(lp[,1] > 0)){
      # Now we go through each placholder
      for(pidx in seq_len(nrow(lp))){
        ppt <- ph_with(x=ppt, value = textstr[pidx], location = ph_location_type(type = lp$type[pidx], id = id[pidx]))
      }
    }
  }

  if(!is.null(output_file)){
    print(ppt, target = output_file)
  }

  ppt
}

#' @export
#' @title get PowerPoint slide content in a tidy format
#' @description get content and positions of current slide
#' into a data.frame. Data for any tables, images, or paragraphs are
#' imported into the resulting data.frame.
#' @note
#' The column \code{id} of the result is not to be used by users.
#' This is a technical string id whose value will be used by office
#' when the document will be rendered. This is not related to argument
#' \code{index} required by functions \code{ph_with_zzz}.
#' @param x rpptx object
#' @param index slide index
#' @examples
#' library(magrittr)
#'
#' my_pres <- read_pptx() %>%
#'   add_slide(layout = "Two Content", master = "Office Theme") %>%
#'   ph_with_text(type = "dt", str = format(Sys.Date())) %>%
#'   add_slide(layout = "Title and Content", master = "Office Theme")
#'
#' slide_summary(my_pres)
#' slide_summary(my_pres, index = 1)
slide_summary <- function( x, index = NULL ){

  l_ <- length(x)
  if( l_ < 1 ){
    stop("presentation contains no slide", call. = FALSE)
  }

  if( is.null(index) )
    index <- x$cursor

  if( !between(index, 1, l_ ) ){
    stop("unvalid index ", index, " (", l_," slide(s))", call. = FALSE)
  }

  slide <- x$slide$get_slide(index)

  nodes <- xml_find_all(slide$get(), as_xpath_content_sel("p:cSld/p:spTree/") )
  data <- read_xfrm(nodes, file = "slide", name = "" )
  data$text <- sapply(nodes, xml_text )
  data[["offx"]] <- data[["offx"]] / 914400
  data[["offy"]] <- data[["offy"]] / 914400
  data[["cx"]] <- data[["cx"]] / 914400
  data[["cy"]] <- data[["cy"]] / 914400

  data$name <- NULL
  data$file <- NULL
  data$ph <- NULL
  data
}






#' @export
#' @title color scheme
#' @description get master layout color scheme into a data.frame.
#' @param x rpptx object
#' @examples
#' x <- read_pptx()
#' color_scheme ( x = x )
color_scheme <- function( x ){
  x$masterLayouts$get_color_scheme()
}
