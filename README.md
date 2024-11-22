# SAS
Example SAS codes

## sql_casestudy.sas
This code was written as the final project for the SAS SQL class, so it's written almost exclusively using proc sql and is only sparsely commented.  It involves cleaning of raw TSA claims data from a .csv file, summarizing and merging with airport data, performing some summary analyses and outputting these to a .pdf report.

## deidentify.sas
Macro to remove identifying ID, Age, and Date variables from CDISC datasets.  This macro was written as part of a training exercise and is not used in production programming.

My goals when writing this code were to allow some user flexibility (e.g. allow a user to declare than a variable that the macro flagged for deletion should instead be kept) as well as help the user investigate inconsistencies that might need to be adjusted in their datasets prior to deidentification (e.g. comparing variable names with their labels based on keywords to suggest a user might want to, for instance, keep a variable that ends in "ID" but does not contain the word "Identifier" in the label).
