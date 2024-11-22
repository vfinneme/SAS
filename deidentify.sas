/******************************************************************************/
/* PROD PROGRAM:    /home/programs/macros/deidentify.sas
/* 
/* PURPOSE:         Remove identifying ID, Age, and Date variables from datasets.
/*                  Add Random ID and age group variables from ADSL (by USUBJID),
/*                  replace Date variables with Day variable (calculated from RFSDT) 
/*                         
/* SOURCE PRGM:     none 
/*
/* INPUT:           Either a libref for datasets or a list of datasets
/*                    - Datasets must be CDISC/CBAR-compliant ADaM or SDTM+
/*                    - At a minimum, an ADSL dataset with deidentifying random
/*                      ID, age grouping, and reference date must be supplied
/*
/* OUTPUT:          Deidentified dataset(s) by the same name in a new directory
/*                    - All ID variables (except STUDYID) are removed
/*                    - USUBJID is replaced with the random ID variable
/*                    - Age variables are replaced with age grouping variable
/*                    - Date variables replaced with Day variables (calculated
/*                      based on reference start date from ADSL)
/*                    - Any birthdate, date-time or character date/date-time 
/*                      variables are removed
/*
/* MACROS USED:     %auditloc, %dataexst, %nobs, %paramreq, %permset, %pgmsrc, %varexst
/* EXEMPTIONS:      none
/*
/* AUTHOR:          Valerie Finnemeyer
/* CREATION DATE:   11SEP2024
/*
/* NOTES:           none
/*
/* MODIFICATIONS:   none 
/******************************************************************************/

%macro deidentify(  INDATA      =       /* (R) List of datasets to deidentify   */
                                        /*           ------OR------             */
                 ,  INLIB       =       /* (R) Libref of datasets to deidentify */

                 ,  OUTLIB      =       /* (R) Libref for deidentified data     */
                 ,  RANDVAR     =       /* (R) ADSL variable for Random ID      */
                 ,  AGEGRVAR    =       /* (R) ADSL variable for age groups     */
                 ,  REFDTVAR    = RFSDT /* (O) ADSL reference for day calcs     */

                 ,  ADSLDATA    =       /* (O) Dataset with ID/Age-group info   */

                 ,  OV_KEEP     =       /* (O) Override macro to Keep variables 
                                               it would otherwise delete        */
                 ,  OV_DROP     =       /* (O) Override macro to Drop variables 
                                               it would otherwise keep          */
                 ,  DEBUG       = N     /* (O) Enter debug mode                 */
                 ) / minoperator;


/******************************************************************************/
/* DECLARE MACRO VARIABLES LOCAL                                              */
/******************************************************************************/

    %local  __COREPROG  __VERSION   _DATALST    
            _LIBLST     mm          _FULLNM
            ll          ii          _DSN 
            _LBN        __PARMERR   IDVARS_NM                 
            IDVARS_LBL  AGEVARS_NM  AGEVARS_LBL
             DTVARS_NM  DTVARS_LBL  DTVARS_FMT  
            OTHRVARS_NM DROPVARS    _DTLBLS     
            VAR_CHK     vv          kk          
            _VRBLNM     _VARLST     dd             
            _PREFIX     _LBLCHK     jj 
            DYVAR       _DTCHK               
            ;


/******************************************************************************/
/* CHECK PROGRAM VERSION                                                      */
/******************************************************************************/        

    %let __COREPROG = DEIDENTIFY;
    %let __VERSION = INITIAL;

    %auditloc();

/********************************************************/
/* ADD DEBUG OPTION TO PARAMETERS                       */
/********************************************************/
%if %length(&DEBUG)= 0 %then %let DEBUG = Y;
%else                        %let DEBUG = %substr(%upcase(&DEBUG),1,1);

%if &DEBUG = Y %then %do;
   options mprint mlogic mlogicnest source2 symbolgen;
%end;
    

/******************************************************************************/
/* CHECK INPUT PARAMETERS AND VALUES                                          */
/******************************************************************************/
    /*** Verify that OUTLIB, RANDVAR, and AGEGRVAR have been declared.  ***/
    /*** Verify that default value of REFDTVAR has not been cleared ***/
    /*** If not, end sas. Error provided by paramreq. ***/
    %paramreq(OUTLIB RANDVAR AGEGRVAR REFDTVAR);

    /*** Determine how input data has been declared ***/
    /*** If neither INDATA or INLIB have been declared, provide error and end sas ***/
    %if %length(&INDATA)=0 and %length(&INLIB)=0 %then %do;
        %put %upcase(error: (cbar) &__COREPROG -) Must declare either INDATA= OR INLIB=.;
        %abort abend;
    %end;

    /*** If both INDATA and INLIB have been declared, provide error and end sas ***/
    %else %if %length(&INDATA)>0 and %length(&INLIB)>0 %then %do;
        %put %upcase(error: (cbar) &__COREPROG -) Declare INDATA= OR INLIB=.  Cannot declare both.;
        %abort abend;
    %end;

    /*** If just INLIB is declared ***/
    %else %if %length(&INLIB)>0 %then %do; 

        /*** If INLIB is declared, it must be a single libref.  If not write error and end sas ***/
        %if %sysfunc(countw(&INLIB))>1 %then %do;
            %put %upcase(error: (cbar) &__COREPROG -) INLIB must be a single libref.  You declared: &INLIB..;
            %abort abend;
        %end;
        
        /*** Generate _DATALST from it ***/
        %else %do;
            title "Datasets to be processed from &INLIB";
            proc sql 
            %if &DEBUG ^= Y %then %do;
                noprint
            %end;
            ;
                select memname label = "Available Data" 
                    into :_DATALST separated by " "
                    from dictionary.tables
                    where libname = "%upcase(&INLIB)"
                      and memtype = "DATA"
                    ;
            quit;

            /*** Duplicate library to match # of datasets ***/
            /*** &SQLOBS counts how many variables are stored in _DATALST (above) ***/
            %let _LIBLST = ;
            %do mm = 1 %to &SQLOBS;
                %let _LIBLST = &_LIBLST &INLIB;
            %end;
        %end;

    %end;

    /*** If INDATA is a list of datasets, verify that they exist.  If not, end sas. ***/
    /*** If datasets exist, separate libraries from dataset names***/
    %else %do;
        %dataexst(&INDATA);
        %let _LIBLST = ;
        %let _DATALST = ;

        /*** Loop over all listed datasets ***/
        %do ll = 1 %to %sysfunc(countw(&INDATA,%str( )));
            /*** Extract current dataset name ***/
            %let _FULLNM = %scan(&INDATA,&ll,%str( ));

            /*** If it has a . in it, extract libname and datasetname ***/
            %if %sysfunc(find(&_FULLNM,.))>0 %then %do;
                %let _LIBLST   =   &_LIBLST %scan(&_FULLNM,1,.);
                %let _DATALST = &_DATALST %scan(&_FULLNM,2,.);
            %end;

            /*** Otherwise, it is a temporary dataset ***/
            %else %do;
                %let _LIBLST   =   &_LIBLST WORK;
                %let _DATALST = &_DATALST &_FULLNM;
            %end;
        %end;
    %end; 

    /*** If DEBUG, print out final lists to log ***/
    %if DEBUG ^= Y %then %do;
        %put %upcase(note: (cbar) &__COREPROG -) &=_LIBLST;
        %put %upcase(note: (cbar) &__COREPROG -) &=_DATALST;
    %end;


    /**************************
    *** Verify ADSL Dataset ***
    **************************/   
    /*** If ADSLDATA is not specified, look for adsl dataset in _DATALST ***/  
    %if %length(&ADSLDATA) = 0 %then %do;
        /*** If ADSL exists, set ADSLDATA to it ***/
        %if %sysfunc(findw(%upcase(&_DATALST),ADSL,%str(" "),e)) ne 0 %then %do;
            %let ADSLDATA = %scan(%upcase(&_LIBLST),%sysfunc(findw(%upcase(&_DATALST),ADSL,%str(" "),e))).ADSL;
        %end;

        /*** Otherwise, issue error to require user to specify ***/
        %else %do;
            %put %upcase(error: (cbar) &__COREPROG -) ADSL dataset not found.;  
            %put %upcase(error: (cbar) &__COREPROG -) Please verify ADSL is in specified directory or specify alternative key source ADSLDATA = ;
            %abort abend;
        %end;
    %end;


    /********************************************************
    *** Verify that all reference variables exist in ADSL ***
    ********************************************************/
    /*** If not, varexst will end SAS and provide error ***/
    %varexst(&ADSLDATA,&RANDVAR &AGEGRVAR &REFDTVAR USUBJID,Update dataset or macro call,ENDSAS);

    /************************************************************
    *** Verify that ADSL contains only one record per USUBJID ***
    ************************************************************/
    /*** Sort to find duplicate records ***/
    proc sort data=&ADSLDATA nodupkey out=_null_ dupout=adsldup;
        by USUBJID;
    run;

    /*** If duplicate records dataset exists and contains observations ***/
    /*** Print error in log, print duplicates to list file, and end sas ***/
    %if %sysfunc(exist(adsldup)) and %nobs(adsldup) > 0 %then %do;
        %put %upcase(error: (cbar) &__COREPROG -) ADSL contains duplicates per USUBJID.  See .lst for details;  

        title "Duplicate USUBJID records within &ADSLDATA";
        proc print data=adsldup;
        run;

        %abort abend;
    %end;
    

    /********************************
    *** Check OV_KEEP and OV_DROP ***
    ********************************/
    /*** If OV_KEEP contains USUBJID or BRTHDT, remove from list and provide warning in log ***/
    %if %sysfunc(find(%upcase(&OV_KEEP),USUBJID))>0 %then %do;
        %let OV_KEEP = %sysfunc(prxchange(s!\bUSUBJID\b!!,1,%upcase(&OV_KEEP)));
        %put %upcase(warning: (cbar) &__COREPROG -) USUBJID cannot be retained.  It has been removed from OV_KEEP;
    %end;

    %if %sysfunc(find(%upcase(&OV_KEEP),BRTHDT))>0 %then %do;
        %let OV_KEEP = %sysfunc(prxchange(s!\bBRTHDT\b!!,1,%upcase(&OV_KEEP)));
        %put %upcase(warning: (cbar) &__COREPROG -) BRTHDT cannot be retained.  It has been removed from OV_KEEP;
    %end;

    /*** Verify that OV_KEEP and OV_DROP do not contain any overlaps ***/
    %if &OV_KEEP > 0 %then %do;
        %do ii = 1 %to %sysfunc(countw(&OV_KEEP));
            /*** At the first common variable found, write error to log and end sas ***/
            %if %sysfunc(find(%upcase(&OV_DROP),%sysfunc(scan(%upcase(&OV_KEEP,&ii))))) > 0 %then %do;
                %put %upcase(error: (cbar) &__COREPROG -) OV_KEEP and OV_DROP have at least one common variable.;
                %put %upcase(error: (cbar) &__COREPROG -) Remove commonalities and resubmit.;
                %abort abend;
            %end;
        %end;
    %end;


/***************************************************
*** Remove identifying information from datasets ***
***************************************************/
    /*** Loop over all datasets ***/
    %do ii = 1 %to %sysfunc(countw(&_DATALST));
        %let _DSN = %upcase(%scan(&_DATALST,&ii));
        %let _LBN = %upcase(%scan(&_LIBLST,&ii));
        %let __PARMERR = 0;

        /*** If dataset does not have USUBJID, output note to log and skip ***/
        %varexst(&_LBN..&_DSN,USUBJID);
        %if &__PARMERR %then %do;
            %put %upcase(note: (cbar) &__COREPROG -) &_DSN does not contain USUBJID and will not be processed;
        %end;

        /*** If dataset does not contain observations, output note to log and skip ***/
        %else %if %nobs(&_LBN..&_DSN) = 0 %then %do;
            %put %upcase(warning: (cbar) &__COREPROG -) &_DSN has no observations and will not be processed;
        %end;

        /*** If OUTLIB is the same as _LBN, output a note to log ***/
        %else %if "%sysfunc(pathname(&_LBN))" = "%sysfunc(pathname(&OUTLIB))" %then %do;
            %put %upcase(warning: (cbar) &__COREPROG -) &_DSN is being sourced from your requested output directory: &OUTLIB;
            %put %upcase(warning: (cbar) &__COREPROG -) To avoid overwriting, this dataset will not be processed;
        %end;

        /*** Otherwise, continue with deidentification ***/
        %else %do;


            /*** Initialize macro variables storing variable lists ***/
            %let IDVARS_NM = ;
            %let IDVARS_LBL = ;
            %let AGEVARS_NM = ;
            %let AGEVARS_LBL = ;
            %let DTVARS_NM = ;
            %let DTVARS_LBL = ;
            %let DTVARS_FMT = ;
            %let OTHRVARS_NM = ;
            %let DROPVARS = ;

            proc sql
            %if &DEBUG ^= Y %then %do;
                noprint
            %end;
            ;
            title "Searching for Possible ID Variables";
            /*** Find all ID variables ***/
            /*** Search all variable labels for the word "Identifier" (not RANDVAR or STUDYID) ***/
                select name label="Possible ID in &_DSN Based on Label"
                    into :IDVARS_LBL separated by " "
                    from dictionary.columns
                    where   libname =   "&_LBN"
                        and memtype =   "DATA"
                        and memname =   "&_DSN"
                        and name    ne  "STUDYID"
                        and name    ne  %upcase("&RANDVAR")
                        and findw(label,"Identifier"," ","i") ne 0
                        ;

            /*** Search all variable names for those ending in "ID" (not RANDVAR or STUDYID) ***/
                select name label="Possible ID Variables in &_DSN Based on Name"
                    into :IDVARS_NM separated by " "
                    from dictionary.columns
                    where   libname =   "&_LBN"
                        and memtype =   "DATA"
                        and memname =   "&_DSN"
                        and name    ne  "STUDYID"
                        and name    ne  %upcase("&RANDVAR")
                        and substr(upcase(name),length(name)-1,2) = "ID"
                        ;


            /*** Find all Age variables ***/
            title "Searching for Possible AGE Variables";
            /*** Search all variable labels for the word "Age" (not AGEGRVAR) ***/
                select name label="Possible Age in &_DSN Based on Label"
                    into :AGEVARS_LBL separated by " "
                    from dictionary.columns
                    where   libname =   "&_LBN"
                        and memtype =   "DATA"
                        and memname =   "&_DSN"
                        and name    ne  "&AGEGRVAR"
                        and findw(label,"Age"," ","i") ne 0
                        ;

            /*** Search all variable names for those beginning with AGE (not AGEGRVAR) ***/
                select name label="Possible Age Variables in &_DSN Based on Name"
                    into :AGEVARS_NM separated by " "
                    from dictionary.columns
                    where   libname =   "&_LBN"
                        and memtype =   "DATA"
                        and memname =   "&_DSN"
                        and name    ne  "&AGEGRVAR"
                        and substr(upcase(name),1,3) = "AGE"
                        ;



            /*** Find all Date variables ***/
            title "Searching for Possible Date Variables";
            /*** Search all variable labels for the word "Date" ***/
            /*** (not BRTHDT, DTM, &REFDTVAR) ***/ 
                select name label="Possible Date in &_DSN Based on Label"
                    into :DTVARS_LBL separated by " "
                    from dictionary.columns
                    where   libname =   "&_LBN"
                        and memtype =   "DATA"
                        and memname =   "&_DSN"
                        and name    ne  "BRTHDT"
                        and name    ne  "&REFDTVAR"
                        and substr(upcase(name),length(name)-2,3) ne "DTM"
                        and findw(label,"Date"," ","i") ne 0
                        ;

            /*** Search all variable names for those ending in DT  ***/
            /*** (not BRTHDT, DTM, &REFDTVAR) ***/
            /*** Save associated labels for later use ***/
                select name label="Possible Date Variables in &_DSN Based on Name",
                       label label="Labels Associated with Date Variables in &_DSN"
                    into :DTVARS_NM separated by " ",
                         :_DTLBLS separated by "|"
                    from dictionary.columns
                    where   libname =   "&_LBN"
                        and memtype =   "DATA"
                        and memname =   "&_DSN"
                        and name    ne  "BRTHDT"
                        and name    ne  "&REFDTVAR"
                        and substr(upcase(name),length(name)-2,3) ne "DTM"
                        and substr(upcase(name),length(name)-1,2) = "DT"
                        ;

            /*** Search all variables with Date9. format  ***/
            /*** (not BRTHDT, DTM, &REFDTVAR) ***/
                select name label="Possible Date Variables in &_DSN Based on Name"
                    into :DTVARS_FMT separated by " "
                    from dictionary.columns
                    where   libname =   "&_LBN"
                        and memtype =   "DATA"
                        and memname =   "&_DSN"
                        and name    ne  "BRTHDT"
                        and name    ne  "&REFDTVAR"
                        and format  =   "DATE9."
                        ;


            /*** Find other variables to be removed ***/
            title "Searching for Other Variables to Remove";
            /*** Find other exceptions (BRTHDT) or DTM variables based on name only ***/
                select name label="Other variables to be removed from &_DSN"
                    into :OTHRVARS_NM separated by " "
                    from dictionary.columns
                    where   libname = "&_LBN"
                        and memtype = "DATA"
                        and memname = "&_DSN"
                        and (name   = "BRTHDT"
                             or substr(upcase(name),length(name)-2,3) = "DTM")
                        ;


            quit;

            /****************************************************
            *** Flag possible inconsistencies for user review ***
            ****************************************************/
            /*** If any ID variables do not contain "Identifier" in label, flag for review ***/ 
            %if &IDVARS_NM> 0 %then %do;
            %let VAR_CHK = ;
                %do vv = 1 %to %sysfunc(countw(&IDVARS_NM,%str(" ")));
                    %if %sysfunc(find(&IDVARS_LBL,%sysfunc(scan(&IDVARS_NM,&vv)))) = 0 %then %do;
                        %let VAR_CHK = &VAR_CHK %scan(&IDVARS_NM,&vv);
                    %end;
                %end;

                %if &VAR_CHK > 0  %then %do;
                    %put %upcase(note: (cbar) &__COREPROG -) Variables ending in "ID" that do not have "Identifier" in label in &_DSN.:;
                    %put %upcase(note: (cbar) &__COREPROG -) &VAR_CHK..;
                    %put %upcase(note: (cbar) &__COREPROG -) If these variables should not be removed, please override with OV_KEEP=.;
                %end;
            %end;

            /*** If any Age variables do not contain "Age" in label, flag for review ***/
            %if &AGEVARS_NM > 0 %then %do;
                %let VAR_CHK = ;
                %do vv = 1 %to %sysfunc(countw(&AGEVARS_NM,%str(" ")));
                    %if %sysfunc(find(&AGEVARS_LBL,%sysfunc(scan(&AGEVARS_NM,&vv)))) = 0 %then %do;
                        %let VAR_CHK = &VAR_CHK %scan(&AGEVARS_NM,&vv);
                    %end;
                %end;

                %if &VAR_CHK > 0  %then %do;
                    %put %upcase(note: (cbar) &__COREPROG -) Variables names containing "AGE" that do not have "Age" in label in &_DSN.:;
                    %put %upcase(note: (cbar) &__COREPROG -) &VAR_CHK..;
                    %put %upcase(note: (cbar) &__COREPROG -) If these variables should not be removed, please override with OV_KEEP=.;
                %end;
            %end;

            /*** If any Date variables do not contain "Date" in label, flag for review ***/
            %if &DTVARS_NM > 0 %then %do;
                %let VAR_CHK = ;
                %do vv = 1 %to %sysfunc(countw(&DTVARS_NM,%str(" ")));
                    %if %sysfunc(find(&DTVARS_LBL,%sysfunc(scan(&DTVARS_NM,&vv)))) = 0 %then %do;
                        %let VAR_CHK = &VAR_CHK %scan(&DTVARS_NM,&vv);
                    %end;
                %end;

                %if &VAR_CHK > 0 %then %do;
                    %put %upcase(note: (cbar) &__COREPROG -) Variables names ending in "DT" that do not have "Date" in label in &_DSN.:;
                    %put %upcase(note: (cbar) &__COREPROG -) &VAR_CHK..;
                    %put %upcase(note: (cbar) &__COREPROG -) If these variables should not be removed, please override with OV_KEEP=;
                %end;
            %end;

            /**********************************************************
            *** Make final list of variables to remove from dataset ***
            **********************************************************/
            /*** Remove OV_KEEP from lists ***/
            %if %sysfunc(countw(&OV_KEEP,%str(" "))) > 0 %then %do;
                %do kk = 1 %to %sysfunc(countw(&OV_KEEP));
                    %let _VRBLNM = %upcase(%scan(&OV_KEEP,&kk));

                    /*** If present in DTVARS_NM, also remove associated label from list ***/
                    %if %sysfunc(findw(%upcase(&DTVARS_NM),&_VRBLNM)) > 0 %then %do;

                        /*** If this variable is in Date9. format, do not remove it and provide warning in log ***/
                        %if %sysfunc(find(&DTVARS_FMT,&_VRBLNM))>0 %then %do;
                            %put %upcase(warning: (cbar) &__COREPROG -) &_VRBLNM in &_DSN is in Date9. format and will not be removed.;
                        %end;

                        %else %do;

                            /*** Find label associated with this DT variable ***/
                            %let _LBLCHK = %scan(&_DTLBLS,%sysfunc(findw(%upcase(&DTVARS_NM),&_VRBLNM,%str(" "),e)),|);

                            /*** Remove associated label and any pipe that comes after it ***/
                            %let _DTLBLS =  %sysfunc(prxchange(s!&_LBLCHK\|?!!,1,&_DTLBLS)); 

                            /*** Remove DT variable from list ***/
                            %let DTVARS_NM =       %sysfunc(prxchange(s!\b&_VRBLNM\b!!,1,%upcase(&DTVARS_NM)));
                        %end;
                    %end;

                    /*** Search for _VRBLNM as a stand-alone word in list and, if present, remove ***/
                    %let IDVARS_NM =       %sysfunc(prxchange(s!\b&_VRBLNM\b!!,1,%upcase(&IDVARS_NM)));
                    %let AGEVARS_NM =      %sysfunc(prxchange(s!\b&_VRBLNM\b!!,1,%upcase(&AGEVARS_NM)));
                    %let OTHRVARS_NM =     %sysfunc(prxchange(s!\b&_VRBLNM\b!!,1,%upcase(&OTHRVARS_NM)));
                %end;
            %end;

            /*** Add OV_DROP if they exist in this dataset ***/
            proc sql noprint;
                select name 
                    into :_VARLST separated by " "
                    from dictionary.columns
                    where   libname = "&_LBN"
                        and memtype = "DATA"
                        and memname = "&_DSN"
                        ;
            quit;

            %if OV_DROP > 0 %then %do;
                %do dd = 1 %to %sysfunc(countw(&OV_DROP,%str(" ")));
                    %let _VRBLNM = %upcase(%scan(&OV_DROP,&dd));
                    %if &_VRBLNM in (&_VARLST) %then %let DROPVARS = &DROPVARS &_VRBLNM;
                %end;
            %end;

            /*** Make final list of variables to remove from dataset ***/
            %let DROPVARS = &DROPVARS &IDVARS_NM &AGEVARS_NM &DTVARS_NM &OTHRVARS_NM;

            /*** Remove DT from the end of every word in list ***/
            %let _PREFIX = %sysfunc(prxchange(s!\BDT\b!!,-1,&DTVARS_NM));


          /**********************************************************************
          *** Merge dataset with ADSL based on USUBJID and delete identifiers ***
          **********************************************************************/
            data &OUTLIB..&_DSN(drop = &DROPVARS &REFDTVAR)
                /*** Keep track of records in this dataset without a matching USUBJID ***/
                noadsl_&_DSN(keep= USUBJID)
                ;

                merge &_LBN..&_DSN (in=indat)
                      &ADSLDATA(    in=inkey
                                    keep = USUBJID &RANDVAR &AGEGRVAR &REFDTVAR);
                by USUBJID;

                /*** If this USUBJID exists in dataset and ADSL, continue to process ***/
                if indat and inkey then do;

                /*** Calculate day variables if date variables exist ***/
                    %if &DTVARS_NM > 0 %then %do;
                /*** Loop over all date variables ***/
                        %do jj = 1 %to %sysfunc(countw(&DTVARS_NM),%str(" "));
                            %let DYVAR = %scan(&_PREFIX,&jj)DY;

                            /*** Calculate day relative to start date provided from KEY ***/
                            &DYVAR = %scan(&_PREFIX,&jj)DT-&REFDTVAR+1;
                            /*** Accounting for CDISC standard of no Day 0 ***/
                            %if &DYVAR<1 %then %do;
                                &DYVAR = &DYVAR - 1;
                            %end;

                            /*** Capture DT datalabel and replace "Date" with "Day" in it ***/
                            %let _DTCHK = %scan(&_DTLBLS,&jj,%str(|));
                            label &DYVAR = "%sysfunc(prxchange(s!Date!Day!,-1,&_DTCHK))";

                        %end;
                    %end;
                    output &OUTLIB..&_DSN;
                end;

                if indat and not inkey then output noadsl_&_DSN;
            run;

            %if %sysfunc(exist(noadsl_&_DSN)) and %nobs(noadsl_&_DSN) > 0 %then %do;
                %put %upcase(warning: (cbar) &__COREPROG -) &_DSN contains records without matching USUBJID in &ADSLDATA.;  
                %put %upcase(warning: (cbar) &__COREPROG -) These records are not included in deidentified dataset.;
                %put %upcase(warning: (cbar) &__COREPROG -) See .lst for details;  

                title "Records in &_DSN without deidentification keys in ADSL";
                proc print data=noadsl_&_DSN;
                run;
            %end;


            /*** Label the output dataset ***/
            %if %substr(&_DSN,1,2) ne AD %then %do;
                %pgmsrc(INDATA = &OUTLIB..&_DSN,
                        LABEL  = Deidentified SDTM+ Dataset: &_DSN,
                        FILE   = YES);
            %end;
            %else %do;
                %pgmsrc(INDATA = &OUTLIB..&_DSN,
                        LABEL  = Deidentified ADaM Dataset: &_DSN,
                        FILE   = YES);
            %end;

            /*** Set dataset permissions ***/
            %permset(indata=&OUTLIB..&_DSN);

        %end;  /* Processing datasets with USUBJID */

        %put %upcase(note: (cbar) &__COREPROG -) Removed from &_DSN for deidentification:;
        %put %upcase(note: (cbar) &__COREPROG -) &DROPVARS; 

    %end;  /* Loop over all provided datasets */

%mend deidentify;
