libname sq "/home/u63852457/TSA";

options validvarname=v7;

proc import datafile="/home/u63852457/ECRB94/data/TSAClaims2002_2017.csv" 
	dbms=csv out=sq.claims_cleaned replace;
	guessingrows=max;
run;

%let StartYear = 2013;
%let EndYear = 2017;

/* Clean-up invalid data */
proc sql;
create table sq.Claims_Cleaned as 
select distinct Claim_Number, Incident_Date,
	case 
		when Incident_Date<Date_Received then Date_Received
		else intnx('year',Date_Received,1,'same')
	end as Date_Received label="Date Received",
	case 
		when Airport_Code is null then "Unknown"
		else upcase(Airport_Code) 
	end as Airport_Code label= "Airport Code",
	propcase(Airport_Name) as Airport_Name,
	case 
		when Claim_Type is null then "Unknown"
		else scan(Claim_Type,1,'/')
	end as Claim_Type label = "Claim Type", 
	case
		when Claim_Site is null then "Unknown"
		else Claim_Site
	end as Claim_Site label = "Claim Site", 
	Close_Amount format=dollar10.2 label = "Close Amount",
	case
		when Disposition is null then "Unknown"
		when scan(Disposition,2,': ')= "Contractor" then "Closed:Contractor Claim"
		when scan(Disposition,2,': ')= "Canceled" then "Closed:Canceled"
		else Disposition	
	end as Disposition,
	propcase(StateName) as StateName label = "State Name", 
	upcase(State) as State,
	propcase(County) as County, propcase(City) as City
	from sq.claimsraw
	where year(Incident_Date) between &StartYear and &EndYear
	order by Airport_Code, Incident_Date;
quit;

/* sort and group data */
proc sql;
create view sq.claims_summary as
select distinct Airport_Code, Airport_Name, City, State,
	year(Incident_Date) as Year, count(*) as TotalClaims
	from sq.Claims_Cleaned
	group by Airport_Code, Year
	order by Airport_Code, Year;
quit;

/* combine with passenger boarding data */
proc sql;
create table sq.ClaimsbyAirport as
select c.Airport_Code, c.Airport_Name, c.City, c.State,
	c.Year, b.Enplanement, c.TotalClaims, 
	c.TotalClaims/b.Enplanement as PctClaims format=percent3.2
	from sq.claims_summary as c inner join
		(select LocID, input(Year,4.) as Year, Enplanement
			from sq.enplanement2017
			outer union corr
		select LocID, Year, Boarding as Enplanement
			from sq.boarding2013_2016) as b
	on c.Airport_Code = b.LocID and c.Year = b.Year
	;
quit;

ods graphics on;
ods pdf file="/home/u63852457/TSA/tsareport.pdf";
ods noproctitle;

/* How many claims per year of Incident_Date in the Overall Data*/
title "Claims Per Year";
proc freq data=sq.Claims_Cleaned;
	tables Incident_Date / plots=freqplot(type=bar);
	format Incident_Date year4.;
run;

%let state=HI;

title "Claims in &state";
title2 "Claims Frequency";
proc freq data=sq.Claims_Cleaned order=freq;
	where State=upcase("&State");
	tables Claim_Type Claim_Site Disposition / nocum nopercent;
run;

title2 "Cost Analysis";
proc means data=sq.Claims_Cleaned mean min max sum maxdec=0;
	where State=upcase("&State");
	var Close_Amount;
run;

ods pdf close;
ods proctitle;
