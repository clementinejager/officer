% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/ppt_ph_manipulate.R
\name{ph_add_par}
\alias{ph_add_par}
\title{append paragraph}
\usage{
ph_add_par(x, type = "body", id = 1, id_chr = NULL, level = 1,
  ph_label = NULL)
}
\arguments{
\item{x}{a pptx device}

\item{type}{placeholder type}

\item{id}{placeholder index for a duplicated type(integer). This is to be used when a placeholder
type is not unique in the layout of the current slide, e.g. two placeholders with type 'body'. To
add onto the first, use \code{id = 1} and \code{id = 1} for the second one.
Values can be read from \code{\link{slide_summary}}.}

\item{id_chr}{deprecated.}

\item{level}{paragraph level}

\item{ph_label}{label associated to the placeholder. Use column
\code{ph_label} of result returned by \code{\link{slide_summary}}.}
}
\description{
append a new empty paragraph in a placeholder
}
\examples{
library(magrittr)

fileout <- tempfile(fileext = ".pptx")
default_text <- fp_text(font.size = 0, bold = TRUE, color = "red")

doc <- read_pptx() \%>\%
  add_slide(layout = "Title and Content", master = "Office Theme") \%>\%
  ph_with("A text", location = ph_location_type(type = "body")) \%>\%
  ph_add_par(level = 2) \%>\%
  ph_add_text(str = "and another, ", style = default_text ) \%>\%
  ph_add_par(level = 3) \%>\%
  ph_add_text(str = "and another!",
              style = update(default_text, color = "blue"))

print(doc, target = fileout)
}
