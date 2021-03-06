library(openxlsx)
library(dplyr)
library(stringi)

## DATA CRUNCH (Pre-processing) --------

  # Tab.1. Data Crunh --------

current_trustee_subset <- c("TF072236","TF072584", "TF072129","TF071630")
current_trustee_subset <- active_trustee %>%
  filter(Fund %in% c("TF072236","TF072584", "TF072129","TF071630")) %>%
  select(temp.name) 

as.of.date <- date_data_udpated

old_processed_data <- process_data_files(
  GRANTS_file = old_grants_file,
  TRUSTEE_file = old_trustee_file,
  date_pos = 2
  )

old_data <- old_processed_data[['report_grants']] %>% filter(PMA=='no')

data <- report_grants %>% filter(PMA=='no')

region <- 'ALL regions'

funding_sources <- active_trustee$temp.name %>% 
  unique() %>%
  paste(sep = "",collapse= "; ")

current_trustee_subset_collapsed <- sort(current_trustee_subset$temp.name)%>% 
  unique() %>%
  paste(sep = "",collapse= "; ")

df_treatment <- function(Data=data){
  
  df <- Data %>%
    select(
      `Closing FY`,
      `Trustee #`,
      `Trustee Fund Name`,
      `Child Fund #`,
      `Project ID`,
      `Child Fund Name`,
      `Child Fund Status`,
      `Execution Type`,
      `Child Fund TTL Name`,
      `Managing Unit`,
      `Lead GP/Global Theme`,
      Country,
      `Region Name`,
      `Activation Date`,
      `Closing Date`,
      `Grant Amount`,
      `Cumulative Disbursements`,
      `2020 Disbursements`,
      `PO Commitments`,
      `Remaining Available Balance`,
      `Months to Closing Date`,
      `Required Monthly Disbursement Rate`,
      `Disbursement Risk Level`
    )

df$`Uncommitted Balance (Percent)` <- df$`Remaining Available Balance`/df$`Grant Amount`

df$`Grace Period` <- ifelse(df$`Disbursement Risk Level`=="Closed (Grace Period)",
                            "Yes",
                            "No")

df <- df %>%
  arrange(match(`Disbursement Risk Level`,
                c("Closed (Grace Period)","Very High Risk","High Risk","Medium Risk", "Low Risk" )))


df <- df %>% rename("Uncommitted Balance" = `Remaining Available Balance`)
df <- df %>% mutate(GPURL_binary = ifelse(`Lead GP/Global Theme`=="Urban, Resilience and Land",
                                          "GPURL",
                                          "Non-GPURL"))

df$GPURL_binary[is.na(df$GPURL_binary)] <- "Non-GPURL"


return(df)

}


df <- df_treatment()
old_df <- df_treatment(Data=old_data)

df$funding_sources <- paste0(df$`Trustee Fund Name`," (",df$`Trustee #`,")")

trustee_subset_names_number <- sort(unique(df$funding_sources)) %>%
  paste(sep="",collapse="; ")

df <- df %>% select(-funding_sources)




#rm(wb)
wb <- createWorkbook()


options("openxlsx.dateFormat", "mm/dd/yyyy")


sum_df_all <- df %>%
  summarise("# Grants" = n(),
            "$ Amount" = sum(`Grant Amount`),
            "Available Balance (Uncommitted)" = sum(`Uncommitted Balance`)) %>%
  mutate("percent" =`Available Balance (Uncommitted)`/`$ Amount`)

#Changeeeeee
sum_df_all$by_8_2020 <- df %>%
  filter(`Trustee Fund Name` %in% current_trustee_subset$temp.name) %>%
  select(`Uncommitted Balance`) %>% 
  add_row(`Uncommitted Balance`=0) %>% 
  sum()

sum_df_GPURL <- df %>%
  filter(GPURL_binary=="GPURL") %>% 
  summarise("# Grants" = n(),
            "$ Amount" = sum(`Grant Amount`),
            "Available Balance (Uncommitted)" = sum(`Uncommitted Balance`))%>%
  mutate("percent"= `Available Balance (Uncommitted)`/`$ Amount`)

sum_df_GPURL$by_8_2020 <- df %>%
  filter(`Trustee Fund Name` %in%
           current_trustee_subset$temp.name,
         GPURL_binary=="GPURL") %>%
  select(`Uncommitted Balance`) %>%
  add_row(`Uncommitted Balance`=0) %>%  sum()

sum_df_non_GPURL <- df %>%
  filter(GPURL_binary=="Non-GPURL") %>% 
  summarise("# Grants" = n(),
            "$ Amount" = sum(`Grant Amount`),
            "Available Balance (Uncommitted)" = sum(`Uncommitted Balance`)) %>%
  mutate("percent"= `Available Balance (Uncommitted)`/`$ Amount`) 

sum_df_non_GPURL$by_8_2020 <- df %>%
  filter(`Trustee Fund Name` %in% current_trustee_subset$temp.name,
         GPURL_binary=="Non-GPURL") %>%
  select(`Uncommitted Balance`) %>%
  add_row(`Uncommitted Balance`=0) %>% sum()


sum_display_df <- data.frame("Summary" = c("Grant Count",
                                          "Total $",
                                          "Total Available Balance (Uncommitted)",
                                          "Percent Available Balance (Uncommitted)",
                                          paste("Total Available Balance (Uncommitted) under",current_trustee_subset_collapsed)),
                             "GPURL" = unname(unlist(as.list(sum_df_GPURL))),
                             "Non-GPURL" = unname(unlist(as.list(sum_df_non_GPURL))),
                             "Combined Total" = unname(unlist(as.list(sum_df_all))))

names(sum_display_df) <- c("Summary","GPURL","Non-GPURL","Combined Total")



risk_summary <- df %>% group_by(`Disbursement Risk Level`) %>% 
  summarise("Grant Count" = n(),
            "Total Grant Amount" = sum(`Grant Amount`),
            "Total Available Balance (Uncommitted)" = sum(`Uncommitted Balance`))



T_risk_summary <- risk_summary %>% data.table::transpose(l=.)
colnames(T_risk_summary) <- T_risk_summary[1,]
T_risk_summary$Summary <- colnames(risk_summary)
T_risk_summary <- T_risk_summary[-1,]

T_risk_summary$`Total Combined` <-  c(
                       sum(risk_summary$`Grant Count`),
                       sum(risk_summary$`Total Grant Amount`),
                       sum(risk_summary$`Total Available Balance (Uncommitted)`))

T_risk_summary <- T_risk_summary %>% select(Summary,
                                            `Very High Risk`,
                                            `High Risk`,
                                            `Medium Risk`,
                                            `Low Risk`,
                                            `Closed (Grace Period)`,
                                            `Total Combined`)


T_risk_summary <- T_risk_summary %>% mutate(`Very High Risk`=as.numeric(`Very High Risk`),
                                            `High Risk`=as.numeric(`High Risk`),
                                            `Medium Risk`=as.numeric(`Medium Risk`),
                                            `Low Risk`=as.numeric(`Low Risk`),
                                            `Closed (Grace Period)`=as.numeric(`Closed (Grace Period)`),
                                            `Total Combined`=as.numeric( `Total Combined`))

legend_text <- c("Closed. These grants are under the grace period.",
                 "Very High Risk (>10% / month disbursement required)",
                 "High Risk ( > 5%-10% / month disbursement required)",
                 "Medium Risk (3 - 5% / month disbursement required)",
                 "Low Risk (<  3% / month disbursement required)")

report_title <- paste("Disbursement Risk for",region,"as of",as.of.date)
tab_title <- paste0("GFDRR ACTIVE GRANTS (as of ",date_data_udpated,")")

tab.names <- c("Full Grants List","Risk Summary")
funding_sources <- paste("Funding Sources:",trustee_subset_names_number)


  # Tab.2.Data Crunch---------------
all_regions <- sort(unique(df$`Region Name`))

list_dfs <- list()

dfs_to_produce <- c("ALL",all_regions)

summary_risk_tab_2 <- function(temp.region="ALL"){
  
  if (temp.region=="ALL"){
    temp.region <- all_regions}
  
  GPURL <- df %>% 
    filter(`Region Name` %in% temp.region,
           GPURL_binary=="GPURL") %>% 
    group_by(`Disbursement Risk Level`) %>% 
    summarise("Grant Count" = n(),
              "Total Grant Amount" = sum(`Grant Amount`),
              "Total Available Balance (uncommitted)" = sum(`Uncommitted Balance`))
  
  GPURL.2 <- df %>%
    filter(`Trustee Fund Name` %in% current_trustee_subset$temp.name,
           GPURL_binary=="GPURL",
           `Region Name` %in% temp.region) %>%
    group_by(`Disbursement Risk Level`) %>% #,`Trustee Fund Name`) %>% 
    summarise("Available Balance (uncommitted) to Implement by 9/2020"=sum(`Uncommitted Balance`),
              "PO Commitments to spend by 9/2020"=sum(`PO Commitments`)) 
  
  GPURL <- full_join(GPURL,GPURL.2,by="Disbursement Risk Level")
 
  NON.GPURL <- df %>% 
    filter(`Region Name` %in% temp.region,
           GPURL_binary== "Non-GPURL") %>% 
    group_by(`Disbursement Risk Level`) %>% 
    summarise("Grant Count" = n(),
              "Total Grant Amount" = sum(`Grant Amount`),
              "Total Available Balance (uncommitted)" = sum(`Uncommitted Balance`))
  
  NON.GPURL.2 <- df %>%
    filter(`Trustee Fund Name` %in% current_trustee_subset$temp.name,
           GPURL_binary=="Non-GPURL",
           `Region Name` %in% temp.region) %>%
    group_by(`Disbursement Risk Level`) %>% 
    summarise("Available Balance (uncommitted) to Implement by 9/2020"=sum(`Uncommitted Balance`),
              "PO Commitments to spend by 9/2020"=sum(`PO Commitments`))
  
  NON.GPURL <- full_join(NON.GPURL,NON.GPURL.2,by="Disbursement Risk Level")
    
  output <- full_join(GPURL,NON.GPURL,by="Disbursement Risk Level",suffix = c(" (GPURL)", " (Non-GPURL)"))
  
  total_row <- c("Total",
                 sum(output$`Grant Count (GPURL)`,na.rm = TRUE),
                 sum(output$`Total Grant Amount (GPURL)`,na.rm = TRUE),
                 sum(output$`Total Available Balance (uncommitted) (GPURL)`,na.rm = TRUE),
                 sum(output$`Available Balance (uncommitted) to Implement by 9/2020 (GPURL)`,na.rm = TRUE),
                 sum(output$`PO Commitments to spend by 9/2020 (GPURL)`,na.rm = TRUE),
                 sum(output$`Grant Count (Non-GPURL)`,na.rm = TRUE),
                 sum(output$`Total Grant Amount (Non-GPURL)`,na.rm = TRUE),
                 sum(output$`Total Available Balance (uncommitted) (Non-GPURL)`,na.rm = TRUE),
                 sum(output$`Available Balance (uncommitted) to Implement by 9/2020 (Non-GPURL)`,na.rm = TRUE),
                 sum(output$`PO Commitments to spend by 9/2020 (Non-GPURL)`,na.rm = TRUE))
  
  output <- rbind(output, total_row)
  for (j in unique(df$`Disbursement Risk Level`)) {
  
 if (!(j %in% output$`Disbursement Risk Level`)){
   
   new_row <- c(j,rep(NA,8)) 
   output <- rbind(output, new_row)
  
 }
  }
  
  
  output$`Disbursement Risk Level` <- factor(output$`Disbursement Risk Level` ,
                                             levels = c( "Very High Risk",
                                                         "High Risk",
                                                         "Medium Risk",
                                                         "Low Risk",
                                                         "Closed (Grace Period)",
                                                         "Total"))
  
  output <- output %>% arrange(`Disbursement Risk Level`)
  
  output <- output %>%
    mutate(`Grant Count (GPURL)`=as.numeric(`Grant Count (GPURL)`),
           `Total Grant Amount (GPURL)`=as.numeric(`Total Grant Amount (GPURL)`),
           `Total Available Balance (uncommitted) (GPURL)`=as.numeric(`Total Available Balance (uncommitted) (GPURL)`),
           `Available Balance (uncommitted) to Implement by 9/2020 (GPURL)`= as.numeric(`Available Balance (uncommitted) to Implement by 9/2020 (GPURL)`),
           `PO Commitments to spend by 9/2020 (GPURL)` = as.numeric(`PO Commitments to spend by 9/2020 (GPURL)`),
           `Grant Count (Non-GPURL)`= as.numeric(`Grant Count (Non-GPURL)`),
           `Total Grant Amount (Non-GPURL)`= as.numeric(`Total Grant Amount (Non-GPURL)`),
           `Total Available Balance (uncommitted) (Non-GPURL)`= as.numeric(`Total Available Balance (uncommitted) (Non-GPURL)`),
           `Available Balance (uncommitted) to Implement by 9/2020 (Non-GPURL)`= as.numeric(`Available Balance (uncommitted) to Implement by 9/2020 (Non-GPURL)`),
           `PO Commitments to spend by 9/2020 (Non-GPURL)`= as.numeric(`PO Commitments to spend by 9/2020 (Non-GPURL)`))
  
  
  
  
  
  output
}

for (i in 1:length(dfs_to_produce)){
  list_dfs[[dfs_to_produce[i]]] <- summary_risk_tab_2(temp.region = dfs_to_produce[i])
}




## TAB 1. EXCEL ------------------------------------------
addWorksheet(wb, tab.names[1])

writeData(wb,1,
          tab_title,
          startRow = 1,
          startCol = 1)

writeDataTable(wb,1,x = sum_display_df,startCol = 1,startRow = 3,
               withFilter = F,firstColumn = TRUE)

writeDataTable(wb,1,T_risk_summary,startCol = 7, startRow = 3,withFilter = F,
               tableStyle ="TableStyleLight16",firstColumn = TRUE,bandedRows = F)

writeData(wb,1,legend_text,16,3)


RISK.df.row <- 10

excel_df <- df %>% rename("TTL Name" = `Child Fund TTL Name`,
                          "Available Balance (Uncommitted)" = `Uncommitted Balance`) %>%
  select(-c(`Uncommitted Balance (Percent)`,
            `Grace Period`)) %>%
  mutate(
    `Required Monthly Disbursement Rate` = ifelse(
      `Required Monthly Disbursement Rate` == 999,
      NA,
      round(`Required Monthly Disbursement Rate`, digits = 2)
    )
  )

writeDataTable(wb,1,excel_df,
                      startRow = RISK.df.row,
                      startCol = 1)


low_risk <- createStyle(fgFill ="#86F9B7",halign = "left")
medium_risk <- createStyle(fgFill ="#FFE285",halign = "left")
high_risk <- createStyle(fgFill ="#FD8D75",halign = "left")
very_high_risk <- createStyle(fgFill ="#F17979",halign = "left")
grace_period_style <- createStyle(fgFill ="#B7B7B7",halign = "left")

low_risk_rows <- which(df$`Disbursement Risk Level`=="Low Risk")
medium_risk_rows <- which(df$`Disbursement Risk Level`=="Medium Risk")
high_risk_rows <- which(df$`Disbursement Risk Level`=="High Risk")
very_high_risk_rows <- which(df$`Disbursement Risk Level`=="Very High Risk")
grace_period_rows <- which(df$`Disbursement Risk Level`=="Closed (Grace Period)")

for (i in low_risk_rows){
  addStyle(wb,1,rows=i+RISK.df.row,cols=1:length(excel_df),style = low_risk)
}

for (i in medium_risk_rows){
  addStyle(wb,1,rows=i+RISK.df.row,cols=1:length(excel_df),style = medium_risk)
}

for (i in high_risk_rows){
  addStyle(wb,1,rows=i+RISK.df.row,cols=1:length(excel_df),style = high_risk)
}

for (i in very_high_risk_rows){
  addStyle(wb,1,rows=i+RISK.df.row,cols=1:length(excel_df),style = very_high_risk)
}

for (i in grace_period_rows){
  addStyle(wb,1,rows=i+RISK.df.row,cols=1:length(excel_df),style = grace_period_style)
}

header_style <- createStyle(borderColour = getOption("openxlsx.borderColour", "black"),
                            borderStyle = getOption("openxlsx.borderStyle", "thick"),
                            halign = 'center',
                            valign = 'center',
                            textDecoration = NULL,
                            wrapText = TRUE)

dollar_format <- createStyle(numFmt = "ACCOUNTING")
percent_format <- createStyle(numFmt = "0%")
date_format <- createStyle(numFmt = "mm/dd/yyyy")
num_format <- createStyle(numFmt = "NUMBER")
wrapped_text <- createStyle(wrapText = TRUE,valign = "top")
black_and_bold <- createStyle(fontColour = "#000000",textDecoration = 'bold')
merge_wrap <- createStyle(halign = 'center',valign = 'center',wrapText = TRUE)#,border = "TopBottomLeftRight"
addStyle(wb,1,rows=RISK.df.row,cols=1:(length(df)),style = header_style)

number_format_range <- RISK.df.row:(nrow(df)+RISK.df.row)

#addStyle(wb,1,rows=number_format_range,cols=12,style = date_format,stack = TRUE)
addStyle(wb,1,rows=number_format_range,cols=14,style = date_format,stack = TRUE)
addStyle(wb,1,rows=number_format_range,cols=15,style = date_format,stack = TRUE)
addStyle(wb,1,rows=number_format_range,cols=16,style = dollar_format,stack = TRUE)
addStyle(wb,1,rows=number_format_range,cols=17,style = dollar_format,stack = TRUE)
addStyle(wb,1,rows=number_format_range,cols=18,style = dollar_format,stack = TRUE)
addStyle(wb,1,rows=number_format_range,cols=19,style = dollar_format,stack = TRUE)
addStyle(wb,1,rows=number_format_range,cols=20,style = dollar_format,stack = TRUE)
addStyle(wb,1,rows=number_format_range,cols=22,style = percent_format,stack = TRUE)
#addStyle(wb,1,rows=number_format_range,cols=22,style = percent_format,stack = TRUE)
#addStyle(wb,1,rows=number_format_range,cols=23,style = percent_format,stack = TRUE)

setColWidths(wb,1, cols=1:length(df), widths = "auto")
setColWidths(wb,1, cols=2, widths = 15)
setColWidths(wb,1, cols=1, widths = 25)
addStyle(wb,1,rows = 8,cols = 1,style = wrapped_text,stack = TRUE)
addStyle(wb,1,rows = 10,cols = 1:length(df),style = wrapped_text,stack = TRUE)
setColWidths(wb,1, cols=3, widths = 17)
setColWidths(wb,1, cols=4, widths = 17)
setColWidths(wb,1, cols=6, widths = 20) #child fund name
setColWidths(wb,1, cols=7, widths = 9)
setColWidths(wb,1, cols=10, widths = 17)
setColWidths(wb,1, cols=11, widths = 17)
setColWidths(wb,1, cols=12, widths = 13)
setColWidths(wb,1, cols=13, widths = 15)
setColWidths(wb,1, cols=14, widths = 15)
setColWidths(wb,1, cols=16, widths = 14)
setColWidths(wb,1, cols=17, widths = 15)
setColWidths(wb,1, cols=18, widths = 15)
setColWidths(wb,1, cols=19, widths = 15)
setColWidths(wb,1, cols=20, widths = 15)
setColWidths(wb,1, cols=21, widths = 15)
setColWidths(wb,1, cols=22, widths = 15)
setColWidths(wb,1, cols=23, widths = 15)




#ADDITIONAL COLOR COSMETICS

addStyle(wb,1,rows=3,cols = 8, style = very_high_risk)
addStyle(wb,1,rows=4,cols = 15, style = very_high_risk)
addStyle(wb,1,rows=3,cols = 9, style = high_risk)
addStyle(wb,1,rows=5,cols = 15, style = high_risk)
addStyle(wb,1,rows=3,cols = 10, style = medium_risk)
addStyle(wb,1,rows=6,cols = 15, style = medium_risk)
addStyle(wb,1,rows=3,cols = 11, style = low_risk)
addStyle(wb,1,rows=7,cols = 15, style = low_risk)
addStyle(wb,1,rows=3,cols = 12, style = grace_period_style)
addStyle(wb,1,rows=3,cols = 15, style = grace_period_style)

addStyle(wb,1,dollar_format,5,2:4,stack = T)
addStyle(wb,1,dollar_format,6,2:4,stack = T)
addStyle(wb,1,percent_format,7,2:4,stack = T)
addStyle(wb,1,dollar_format,8,2:4,stack = T)

addStyle(wb,1,dollar_format,5,8:13,stack = T)
addStyle(wb,1,dollar_format,6,8:13,stack = T)



##TAB 2. EXCEL---------------------------------
addWorksheet(wb, tab.names[2])

summary_title <- paste0("Summary of GFDRR Active Grants by Risk Category as of ",date_data_udpated,")")

writeData(wb,2,summary_title,startCol = 1,startRow = 1)

writeData(wb,2,names(list_dfs[1]),startCol = 1,startRow = 3)
writeDataTable(wb,2,list_dfs[[1]],startCol = 1,startRow = 5,
               withFilter = F,firstColumn = T,
               tableStyle = "TableStyleLight1")

writeData(wb,2,names(list_dfs[2]),startCol = 1,startRow = 13)
writeDataTable(wb,2,list_dfs[[2]],startCol = 1,startRow = 15,
               withFilter = F,firstColumn = T,
               tableStyle = "TableStyleLight1")


writeData(wb,2,names(list_dfs[3]),startCol = 1,startRow = 23)
writeDataTable(wb,2,list_dfs[[3]],startCol = 1,startRow = 25,
               withFilter = F,firstColumn = T,
               tableStyle = "TableStyleLight1")


writeData(wb,2,names(list_dfs[4]),startCol = 1,startRow = 33)
writeDataTable(wb,2,list_dfs[[4]],startCol = 1,startRow = 35,
               withFilter = F,firstColumn = T,
               tableStyle = "TableStyleLight1")

writeData(wb,2,names(list_dfs[5]),startCol = 13,startRow = 3)
writeDataTable(wb,2,list_dfs[[5]],startCol = 13,startRow = 5,
               withFilter = F,firstColumn = T,
               tableStyle = "TableStyleLight1")


writeData(wb,2,names(list_dfs[6]),startCol = 13,startRow = 13)
writeDataTable(wb,2,list_dfs[[6]],startCol = 13,startRow = 15,
               withFilter = F,firstColumn = T,
               tableStyle = "TableStyleLight1")


writeData(wb,2,names(list_dfs[7]),startCol = 13,startRow = 23)
writeDataTable(wb,2,list_dfs[[7]],startCol = 13,startRow = 25,
               withFilter = F,firstColumn = T,
               tableStyle = "TableStyleLight1")


writeData(wb,2,names(list_dfs[8]),startCol = 13,startRow = 33)
writeDataTable(wb,2,list_dfs[[8]],startCol = 13,startRow = 35,
               withFilter = F,firstColumn = T,
               tableStyle = "TableStyleLight1")


addStyle(wb,2,dollar_format,rows = 6:42,cols = 3,stack = TRUE)
addStyle(wb,2,dollar_format,rows = 6:42,cols = 4,stack = TRUE)
addStyle(wb,2,dollar_format,rows = 6:42,cols = 5,stack = TRUE)
addStyle(wb,2,dollar_format,rows = 6:42,cols = 6,stack = TRUE)
addStyle(wb,2,dollar_format,rows = 6:42,cols = 8,stack = TRUE)
addStyle(wb,2,dollar_format,rows = 6:42,cols = 9,stack = TRUE)
addStyle(wb,2,dollar_format,rows = 6:42,cols = 10,stack = TRUE)
addStyle(wb,2,dollar_format,rows = 6:42,cols = 11,stack = TRUE)



addStyle(wb,2,dollar_format,rows = 6:42,cols = 15,stack = TRUE)
addStyle(wb,2,dollar_format,rows = 6:42,cols = 16,stack = TRUE)
addStyle(wb,2,dollar_format,rows = 6:42,cols = 17,stack = TRUE)
addStyle(wb,2,dollar_format,rows = 6:42,cols = 18,stack = TRUE)
addStyle(wb,2,dollar_format,rows = 6:42,cols = 20,stack = TRUE)
addStyle(wb,2,dollar_format,rows = 6:42,cols = 21,stack = TRUE)
addStyle(wb,2,dollar_format,rows = 6:42,cols = 22,stack = TRUE)
addStyle(wb,2,dollar_format,rows = 6:42,cols = 23,stack = TRUE)

setColWidths(wb,2,cols=c(3,4,5,6,7,8,9,10,11,14,15,16,17,18,20,21,22,23),widths = 15)
setColWidths(wb,2,cols=c(1,11),widths = 17)
addStyle(wb,2,very_high_risk,rows = c(6,16,26,36),cols = 1)
addStyle(wb,2,very_high_risk,rows = c(6,16,26,36),cols = 13)
addStyle(wb,2,high_risk,rows = c(7,17,27,37),cols = 1)
addStyle(wb,2,high_risk,rows = c(7,17,27,37),cols = 13)
addStyle(wb,2,medium_risk,rows = c(8,18,28,38),cols = 1)
addStyle(wb,2,medium_risk,rows = c(8,18,28,38),cols = 13)
addStyle(wb,2,low_risk,rows = c(9,19,29,39),cols = 1)
addStyle(wb,2,low_risk,rows = c(9,19,29,39),cols = 13)
addStyle(wb,2,grace_period_style,rows = c(10,20,30,40),cols = 1)
addStyle(wb,2,grace_period_style,rows = c(10,20,30,40),cols = 13)


writeData(wb,2,"GPURL",startCol = 2,startRow = (4))
writeData(wb,2,"GPURL",startCol = 2,startRow = (14))
writeData(wb,2,"GPURL",startCol = 2,startRow = (24))
writeData(wb,2,"GPURL",startCol = 2,startRow = (34))
writeData(wb,2,"GPURL",startCol = 14,startRow = (4))
writeData(wb,2,"GPURL",startCol = 14,startRow = (14))
writeData(wb,2,"GPURL",startCol = 14,startRow = (24))
writeData(wb,2,"GPURL",startCol = 14,startRow = (34))


writeData(wb,2,"Non-GPURL",startCol = 7,startRow = (4))
writeData(wb,2,"Non-GPURL",startCol = 7,startRow = (14))
writeData(wb,2,"Non-GPURL",startCol = 7,startRow = (24))
writeData(wb,2,"Non-GPURL",startCol = 7,startRow = (34))
writeData(wb,2,"Non-GPURL",startCol = 19,startRow = (4))
writeData(wb,2,"Non-GPURL",startCol = 19,startRow = (14))
writeData(wb,2,"Non-GPURL",startCol = 19,startRow = (24))
writeData(wb,2,"Non-GPURL",startCol = 19,startRow = (34))


mergeCells(wb,2,cols = 1:9,rows = 1)

mergeCells(wb,2,cols = 2:6,rows = 4)
mergeCells(wb,2,cols = 7:11,rows = 4)
mergeCells(wb,2,cols = 14:18,rows = 4)
mergeCells(wb,2,cols = 19:23,rows = 4)

mergeCells(wb,2,cols = 2:6,rows = 14)
mergeCells(wb,2,cols = 7:11,rows = 14)
mergeCells(wb,2,cols = 14:18,rows = 14)
mergeCells(wb,2,cols = 19:23,rows = 14)

mergeCells(wb,2,cols = 2:6,rows = 24)
mergeCells(wb,2,cols = 7:11,rows = 24)
mergeCells(wb,2,cols = 14:18,rows = 24)
mergeCells(wb,2,cols = 19:23,rows = 24)

mergeCells(wb,2,cols = 2:6,rows = 34)
mergeCells(wb,2,cols = 7:11,rows = 34)
mergeCells(wb,2,cols = 14:18,rows = 34)
mergeCells(wb,2,cols = 19:23,rows = 34)

gp_style <- createStyle(fgFill = "#EAE8E8",halign = "center",textDecoration = 'bold')

addStyle(wb,2,gp_style,stack = TRUE,rows = c(4,14,24,34),cols = 2)
addStyle(wb,2,gp_style,stack = TRUE,rows = c(4,14,24,34),cols = 7)
addStyle(wb,2,gp_style,stack = TRUE,rows = c(4,14,24,34),cols = 14)
addStyle(wb,2,gp_style,stack = TRUE,rows = c(4,14,24,34),cols = 19)

addStyle(wb,2,black_and_bold,rows = c(3,13,23,33),cols=1,stack = T)
addStyle(wb,2,black_and_bold,rows = c(3,13,23,33),cols=13,stack = T)


for (f in c(5,15,25,35)){
addStyle(wb,2,wrapped_text,rows= f,cols=1:23)}

for (i in all_regions){
temp_df <- df %>%
  filter(`Region Name` == i)
         #!is.na(`Lead GP/Global Theme`)

#create and old temporary DF to add for comparison
old_temp_df <- old_df %>% filter(`Region Name`==i)

#getsummary df from previoys tab#2 and add it to the regional
temp_risk_summary <- list_dfs[[i]]


#begin creation of other dataframes in the worksheet
regional_sum_display_df <- function (temp_df){

sum_df_all <- temp_df %>%
  summarise("# Grants" = n(),
            "$ Amount" = sum(`Grant Amount`),
            "Available Balance (Uncommitted)" = sum(`Uncommitted Balance`)) %>%
  mutate("percent" =`Available Balance (Uncommitted)`/`$ Amount`)

sum_df_all$uncommitted_8020 <- temp_df %>%
  filter(`Trustee Fund Name` %in% current_trustee_subset$temp.name) %>% 
  select(`Uncommitted Balance`) %>%
  add_row(`Uncommitted Balance`= 0) %>% #add a row in case the df is empty
  sum()

sum_df_all$PO_8020 <- temp_df %>%
  filter(`Trustee Fund Name` %in% current_trustee_subset$temp.name) %>% 
  select(`PO Commitments`) %>%
  add_row(`PO Commitments`= 0) %>% 
  sum()


sum_df_GPURL <-  temp_df %>%
  filter(GPURL_binary=="GPURL") %>% 
  summarise("# Grants" = n(),
            "$ Amount" = sum(`Grant Amount`),
            "Available Balance (Uncommitted)" = sum(`Uncommitted Balance`))%>%
  mutate("percent"= `Available Balance (Uncommitted)`/`$ Amount`)

sum_df_GPURL$uncommitted_8020 <- temp_df %>%
  filter(`Trustee Fund Name` %in% current_trustee_subset$temp.name,
         GPURL_binary=="GPURL") %>% 
  select(`Uncommitted Balance`) %>%
  add_row(`Uncommitted Balance`= 0) %>%
  sum()

sum_df_GPURL$PO_8020 <- temp_df %>%
  filter(`Trustee Fund Name` %in% current_trustee_subset$temp.name,
         GPURL_binary=="GPURL") %>% 
  select(`PO Commitments`) %>%
  add_row(`PO Commitments`= 0) %>% 
  sum()


sum_df_non_GPURL <- temp_df %>%
  filter(GPURL_binary=="Non-GPURL") %>% 
  summarise("# Grants" = n(),
            "$ Amount" = sum(`Grant Amount`),
            "Available Balance (Uncommitted)" = sum(`Uncommitted Balance`))%>%
  mutate("percent"= `Available Balance (Uncommitted)`/`$ Amount`) 

sum_df_non_GPURL$uncommitted_8020 <- 
  temp_df %>%
  filter(`Trustee Fund Name` %in% current_trustee_subset$temp.name,
         GPURL_binary=="Non-GPURL") %>% 
  select(`Uncommitted Balance`) %>%
  add_row(`Uncommitted Balance`= 0) %>% 
  sum()


sum_df_non_GPURL$PO_8020 <- temp_df %>%
  filter(`Trustee Fund Name` %in% current_trustee_subset$temp.name,
         GPURL_binary=="Non-GPURL") %>% 
  select(`PO Commitments`) %>% 
  add_row(`PO Commitments`= 0) %>% 
  sum()


sum_display_df <- data.frame("Summary"= c("Grant Count",
                                          "Total $",
                                          "Total Available Balance (Uncommitted)",
                                          "% Available Balance (Uncommitted)",
                                          "Total $ Available Balance (Uncommitted) Required to Implement by 9/2020 (MDTF, Japan 1, ACP-EU)",
                                          "PO Commitments to spend by 9/2020  (MDTF, Japan 1, ACP-EU)"),
                             "GPURL" = unname(unlist(as.list(sum_df_GPURL))),
                             "Non-GPURL" = unname(unlist(as.list(sum_df_non_GPURL))),
                             "Combined Total" = unname(unlist(as.list(sum_df_all))))

names(sum_display_df) <- c("Summary","GPURL","Non-GPURL"," Combined Total")

sum_display_df <- sum_display_df[-c(3:4),]

return(sum_display_df)}

current_summary <- paste0("Current Summary as of ",report_data_date) 

sum_display_df <- regional_sum_display_df(temp_df) 
                
old_sum_display_df <- regional_sum_display_df(old_temp_df) 

names(old_sum_display_df) <- c(paste0("Previous Month Summary as of ",old_processed_data[["report_data_date"]]),"GPURL","Non-GPURL"," Combined Total")
#---------COUNTRIES DF ----------------------
temp_df_all <- temp_df %>%
  group_by(Country) %>%
  summarise("# Grants" = n(),
            "$ Amount" = (sum(`Grant Amount`)),
            "Available Balance (Uncommitted)" = (sum(`Uncommitted Balance`)))

temp_df_GPURL <- temp_df %>%
  filter(GPURL_binary=="GPURL") %>% 
  group_by(Country) %>%
  summarise("# Grants" = n(),
            "$ Amount" = (sum(`Grant Amount`)),
            "Available Balance (Uncommitted)" = (sum(`Uncommitted Balance`)))

temp_df_non_GPURL <- temp_df %>%
  filter(GPURL_binary=="Non-GPURL") %>% 
  group_by(Country) %>%
  summarise("# Grants" = n(),
            "$ Amount" = (sum(`Grant Amount`)),
            "Available Balance (Uncommitted)" = (sum(`Uncommitted Balance`)))


display_df_partial <- full_join(temp_df_GPURL,
                                temp_df_non_GPURL,
                                by="Country",
                                suffix=c(" (GPURL)"," (Non-GPURL)"))


display_df <- left_join(temp_df_all,display_df_partial,by="Country")

display_df <- display_df %>%  rename("Country/Region"=Country)


#---------FUNDING SOURCE DF ----------------------

temp_df_all <- temp_df %>%
  group_by(`Trustee Fund Name`) %>%
  summarise("# Grants" = n(),
            "$ Amount" = (sum(`Grant Amount`)),
            "PO Commitments"=sum(`PO Commitments`),
            "Available Balance (Uncommitted)" = (sum(`Uncommitted Balance`))
            )

temp_df_GPURL <-  temp_df %>% filter(GPURL_binary=="GPURL") %>% 
  group_by(`Trustee Fund Name`) %>%
  summarise("# Grants" = n(),
            "$ Amount" = (sum(`Grant Amount`)),
            "PO Commitments"=sum(`PO Commitments`),
            "Available Balance (Uncommitted)" = (sum(`Uncommitted Balance`))
            )

temp_df_non_GPURL <- temp_df %>% filter(GPURL_binary=="Non-GPURL") %>% 
  group_by(`Trustee Fund Name`) %>%
  summarise("# Grants" = n(),
            "$ Amount" = (sum(`Grant Amount`)),
            "PO Commitments"=sum(`PO Commitments`),
            "Available Balance (Uncommitted)" = (sum(`Uncommitted Balance`)))


display_df_partial <- full_join(temp_df_GPURL,
                                temp_df_non_GPURL,
                                by="Trustee Fund Name",
                                suffix=c(" (GPURL)"," (Non-GPURL)"))


display_df_funding <- left_join(temp_df_all, display_df_partial , by = "Trustee Fund Name")


#------ CREATE EXCEL WORKBOOK AND ADD DATAFRAMES -------


#temp_df <- reactive_df()
current_summary_title <- paste0("Summary of GFDRR ",i, " Portfolio (as of ",report_data_date,")")
old_summary_title <- paste0("'Previous' Summary of GFDRR ",i, " Portfolio (as of ",old_processed_data['report_data_date'],")")

by_country_title <-   paste0("Grant Details (by Country) as of ",report_data_date)
funding_sources_title <- paste0("Grant Details (by Funding Source) as of ", report_data_date)
  
addWorksheet(wb,i)
# mergeCells(wb,1,c(2,3,4),1)

i <- (which(all_regions==i))+2



writeData(wb,i,old_summary_title,startRow = 2,startCol = 1) 
mergeCells(wb,i,cols = 1,rows = 2:6)
addStyle(wb,i,rows = 2:6, cols = 1, style = merge_wrap,stack = TRUE)

writeData(wb,i,current_summary_title,startRow = 9,startCol = 1)
mergeCells(wb,i,cols = 1,rows = 9:13)
addStyle(wb,i,rows = 9:13, cols = 1, style = merge_wrap,stack = TRUE)

#define row number for start of Grant Detail (by country) table. 
sr <- 15

writeDataTable(wb,i,old_sum_display_df, startRow = 2, startCol = 2, withFilter = F,tableStyle = "TableStyleLight11")
writeDataTable(wb,i,sum_display_df, startRow = 9, startCol = 2, withFilter = F)
writeDataTable(wb,i,temp_risk_summary, startRow = 2, startCol = 7, withFilter = F)
writeDataTable(wb,i,display_df, startRow = sr, startCol = 2,withFilter = F)
writeDataTable(wb,i,display_df_funding, startRow = ((sr+4)+(nrow(display_df))), startCol = 2,withFilter = F)


#FORMULAS FOR TOTALS IN DISPLAY DF  -----------
end_row.display_df <- (sr+nrow(display_df))

writeData(wb,i,by_country_title,startRow = sr,startCol = 1)
mergeCells(wb,i,cols=1,rows=sr:end_row.display_df)
addStyle(wb,i,cols = 1,rows=sr:end_row.display_df, style = merge_wrap,stack = TRUE)


writeFormula(wb,i,x=paste0("=SUM(C",sr,":C",end_row.display_df,")"),startCol = 3,startRow = (end_row.display_df+1))
writeFormula(wb,i,x=paste0("=SUM(D",sr,":D",end_row.display_df,")"),startCol = 4,startRow = (end_row.display_df+1))
writeFormula(wb,i,x=paste0("=SUM(E",sr,":E",end_row.display_df,")"),startCol = 5,startRow = (end_row.display_df+1))
writeFormula(wb,i,x=paste0("=SUM(F",sr,":F",end_row.display_df,")"),startCol = 6,startRow = (end_row.display_df+1))
writeFormula(wb,i,x=paste0("=SUM(G",sr,":G",end_row.display_df,")"),startCol = 7,startRow = (end_row.display_df+1))
writeFormula(wb,i,x=paste0("=SUM(H",sr,":H",end_row.display_df,")"),startCol = 8,startRow = (end_row.display_df+1))
writeFormula(wb,i,x=paste0("=SUM(I",sr,":I",end_row.display_df,")"),startCol = 9,startRow = (end_row.display_df+1))
writeFormula(wb,i,x=paste0("=SUM(J",sr,":J",end_row.display_df,")"),startCol = 10,startRow = (end_row.display_df+1))
writeFormula(wb,i,x=paste0("=SUM(K",sr,":K",end_row.display_df,")"),startCol = 11,startRow = (end_row.display_df+1))

writeData(wb,i,x="Total",startCol = 2,startRow = (end_row.display_df+1))

#FORMULAS FOR TOTALS IN DISPLAY DF FUNDING -----------
start_row.funding <- (sr+nrow(display_df)+5)
end_row.funding <- (sr+nrow(display_df)+4+nrow(display_df_funding))


writeData(wb,i,funding_sources_title,startRow = start_row.funding-1,startCol = 1)
mergeCells(wb,i,cols=1,rows= (start_row.funding-1):end_row.funding)
addStyle(wb,i,rows= (start_row.funding-1):end_row.funding, cols = 1, style = merge_wrap,stack = TRUE)


writeFormula(wb,i,x=paste0("=SUM(C",start_row.funding,":C",end_row.funding,")"),startCol = 3,startRow = (end_row.funding+1))
writeFormula(wb,i,x=paste0("=SUM(D",start_row.funding,":D",end_row.funding,")"),startCol = 4,startRow = (end_row.funding+1))
writeFormula(wb,i,x=paste0("=SUM(E",start_row.funding,":E",end_row.funding,")"),startCol = 5,startRow = (end_row.funding+1))
writeFormula(wb,i,x=paste0("=SUM(F",start_row.funding,":F",end_row.funding,")"),startCol = 6,startRow = (end_row.funding+1))
writeFormula(wb,i,x=paste0("=SUM(G",start_row.funding,":G",end_row.funding,")"),startCol = 7,startRow = (end_row.funding+1))
writeFormula(wb,i,x=paste0("=SUM(H",start_row.funding,":H",end_row.funding,")"),startCol = 8,startRow = (end_row.funding+1))
writeFormula(wb,i,x=paste0("=SUM(I",start_row.funding,":I",end_row.funding,")"),startCol = 9,startRow = (end_row.funding+1))
writeFormula(wb,i,x=paste0("=SUM(J",start_row.funding,":J",end_row.funding,")"),startCol = 10,startRow = (end_row.funding+1))
writeFormula(wb,i,x=paste0("=SUM(K",start_row.funding,":K",end_row.funding,")"),startCol = 11,startRow = (end_row.funding+1))
writeFormula(wb,i,x=paste0("=SUM(L",start_row.funding,":L",end_row.funding,")"),startCol = 12,startRow = (end_row.funding+1))
writeFormula(wb,i,x=paste0("=SUM(M",start_row.funding,":M",end_row.funding,")"),startCol = 13,startRow = (end_row.funding+1))
writeFormula(wb,i,x=paste0("=SUM(N",start_row.funding,":N",end_row.funding,")"),startCol = 14,startRow = (end_row.funding+1))

writeData(wb,i,x="Total",startCol = 2,startRow = (end_row.funding+1))

percent_format <- createStyle(numFmt = "0%")
total_style <- createStyle(bgFill = "#5A52FA",fontColour = "#FFFFFF",textDecoration = "bold")

#add style to "Previous Summary table"
addStyle(wb,i,dollar_format,rows=4,cols=3:5)
addStyle(wb,i,dollar_format,rows=5,cols=3:5)
addStyle(wb,i,dollar_format,rows=6,cols=3:5)

#add style to "Current Summary table"
addStyle(wb,i,dollar_format,rows=11,cols=3:5)
addStyle(wb,i,dollar_format,rows=12,cols=3:5)
addStyle(wb,i,dollar_format,rows=13,cols=3:5)


dollar_columns_Country <- c(4,5,7,8,10,11)

rows.display_df <- sr:(end_row.display_df+1)
rows.display_df_funding <- start_row.funding:(end_row.funding+1)

for (j in dollar_columns_Country){
  addStyle(wb,i,dollar_format,rows=rows.display_df,cols = j)
}

dollar_columns_funding_sources <- c(4,5,6,8,9,10,12,13,14)
for (j in dollar_columns_funding_sources){
  addStyle(wb,i,dollar_format,rows=rows.display_df_funding,cols = j)
}



setColWidths(wb,i, cols = 1:ncol(display_df)+1, widths = "auto")

setColWidths(wb,i, cols =1, widths = 17)
setColWidths(wb,i, cols =2, widths = 60)
setColWidths(wb,i, cols =3, widths = 15)
setColWidths(wb,i, cols =4, widths = 15)
setColWidths(wb,i, cols =5, widths = 17)
setColWidths(wb,i, cols =6, widths = 8)
setColWidths(wb,i, cols =8, widths = 17)
setColWidths(wb,i, cols =9, widths = 8)
setColWidths(wb,i, cols =10, widths = 17)
setColWidths(wb,i, cols =11, widths = 20)
setColWidths(wb,i, cols =12, widths = 15)
setColWidths(wb,i, cols =13, widths = 15)
setColWidths(wb,i, cols =14, widths = 15)
setColWidths(wb,i, cols =15, widths = 15)
setColWidths(wb,i, cols =16, widths = 19)
setColWidths(wb,i, cols =17, widths = 15)

addStyle(wb,i,wrapped_text,cols=2:11,rows = sr,stack = TRUE)
addStyle(wb,i,wrapped_text,cols=2:14,rows = (start_row.funding-1),stack = TRUE)
addStyle(wb,i,wrapped_text,cols=2:17,rows = 3,stack = TRUE)


addStyle(wb,i,very_high_risk,rows = 4,cols = 7)
addStyle(wb,i,high_risk,rows = 5,cols = 7)
addStyle(wb,i,medium_risk,rows = 6,cols = 7)
addStyle(wb,i,low_risk,rows = 7,cols = 7)
addStyle(wb,i,grace_period_style,rows = 8,cols = 7)



#add dollar formats to risk summary regional table
for(ROW in 3:8){
addStyle(wb,i,dollar_format,rows = ROW ,cols=c(9,10,11,12,14,15,16,17))
}

addStyle(wb,i,total_style,rows = 8,cols = 7:17,stack=TRUE)
addStyle(wb,i,total_style,rows = (end_row.display_df+1),cols = 2:11,stack=TRUE)
addStyle(wb,i,total_style,rows = (end_row.funding+1),cols = 2:14,stack=TRUE)

}


if(JAIME_preprocess==FALSE){
#add raw_data tab 
raw_data <- read.xlsx(grants_file)
raw_data <- raw_data %>% filter(Fund %in% df$`Child Fund #`)
addWorksheet(wb,"Raw Data (SAP)")
writeDataTable(wb,sheet="Raw Data (SAP)",x = raw_data)
rm(raw_data)
}


rm(excel_df)




