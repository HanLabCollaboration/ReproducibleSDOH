# The 50 states and DC: the areas covered by the published files.
sdoh_states <- function() {
  c(AL = "01", AK = "02", AZ = "04", AR = "05", CA = "06", CO = "08", CT = "09",
    DE = "10", DC = "11", FL = "12", GA = "13", HI = "15", ID = "16", IL = "17",
    IN = "18", IA = "19", KS = "20", KY = "21", LA = "22", ME = "23", MD = "24",
    MA = "25", MI = "26", MN = "27", MS = "28", MO = "29", MT = "30", NE = "31",
    NV = "32", NH = "33", NJ = "34", NM = "35", NY = "36", NC = "37", ND = "38",
    OH = "39", OK = "40", OR = "41", PA = "42", RI = "44", SC = "45", SD = "46",
    TN = "47", TX = "48", UT = "49", VT = "50", VA = "51", WA = "53", WV = "54",
    WI = "55", WY = "56")
}

# Turn `states` (postal abbreviations or 2-digit FIPS codes) into FIPS codes.
# NULL means every state.
sdoh_state_fips <- function(states) {
  if (is.null(states)) return(NULL)
  table  <- sdoh_states()
  states <- toupper(trimws(as.character(states)))
  is_abbr <- states %in% names(table)
  is_fips <- states %in% table
  invalid <- states[!is_abbr & !is_fips]
  if (length(invalid) > 0) {
    stop(glue::glue(
      "Invalid state(s): {glue::glue_collapse(invalid, sep = ', ')}. ",
      "Use 2-letter postal codes (e.g. \"CA\") or 2-digit FIPS codes (e.g. \"06\") ",
      "for the 50 states or DC."
    ), call. = FALSE)
  }
  unique(ifelse(is_abbr, table[states], states))
}
