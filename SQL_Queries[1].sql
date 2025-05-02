
select * from stg.invoice i;
select * from stg.album;
select * from stg.artist a;
select * from stg.customer c;                                  
select * from stg.employee e;
select * from stg.genre g;
select * from stg.invoiceline il; 
select * from stg.mediatype mt;
select * from stg.playlist p;
select * from stg.playlisttrack pt;
select * from stg.track t;
select * from stg.department_budget db;
select * from stg.dim_currency dcurr;


                       
create table Dim_playlist as( 
                              select pt.playlistid,
                                     pt.trackid,
                                     p.name,
                                     pt.last_update
                              from stg.playlisttrack as pt
                              inner join stg.playlist as p on pt.playlistid = p.playlistid
                             );

create table Dim_customer as(
                              select  c.customerid,
                                      upper(substring(c.firstname from 1 for 1)) || lower(substring(c.firstname from 2)) as first_name,
                                      upper(substring(c.lastname from 1 for 1)) || lower(substring(c.lastname from 2)) as last_name,
                                      c.company,
                                      c.address,
                                      c.city,
                                      c.state,
                                      c.country,
                                      c.postalcode,
                                      c.phone,
                                      c.fax,
                                      c.email,
                                      substring(email from '@(.*)$') as email_domain,
                                      c.supportrepid,
                                      c.last_update
                               from stg.customer as c
                              );




create table Dim_employee as (
                               select 
                                    e.*,
                                    md.department_name,
                                    sum(md.budget) as total_budget,
                                    to_char(age(current_date, hiredate), 'YY "yy" MM "mm"') as seniority,
                                    substring(email from '@(.*)$') as email_domain,
                                    case 
                                       when e.employeeid in (select distinct reportsto from stg.employee where reportsto is not null)
                                       then 1 
                                       else 0 
                                    end as is_manager
                               from stg.employee e
                               inner join stg.merged_df as md on e.departmentid = md.department_id
                               group by distinct e.employeeid, md.department_name
                             );

--אין צורך להביא מטבלת track את העמודות של albumid, mediatypeid, genreid  משום שהן כבר מופיעות בטבלאות שקישרתי אל טבלת הtrack והן המפתחות העיקריים של כל טבלה וטבלה
create table Dim_track as (
                            select t.trackid,
                                   t.name as track_name,
                                   t.composer,
                                   t.milliseconds,
                                   t.milliseconds / 1000.0 as seconds,
                                   to_char(make_interval(secs => (t.milliseconds / 1000.0)::int),'MI "min" SS "sec"') as length,
                                   t.bytes,
                                   t.unitprice,
                                   g.genreid,
                                   g.name as genre_name,
                                   mt.mediatypeid,
                                   mt.name as mediatype_name,
                                   a.albumid,
                                   a.title as album_name,
                                   ar.artistid,
                                   ar.name as artist_name,
                                   t.last_update
                            from stg.track as t
                            left join stg.genre as g on t.genreid = g.genreid
                            left join stg.mediatype as mt on t.mediatypeid = mt.mediatypeid
                            left join stg.album as a on t.albumid = a.albumid
                            left join stg.artist as ar on a.artistid = ar.artistid
                          );


-- אין צורך להביא את שדות הכתובת של טבלת invoice משום שכל השדות הללו נמצאים בטבלת dim_customer
create table Fact_invoice as (
                              select 
                                     i.invoiceid,
                                     i.customerid,
                                     i.invoicedate,
                                     i.total,
                                     i.last_update
                              from stg.invoice i
                             );

create table Fact_invoiceline as (
                                   select
                                          il.invoicelineid,
                                          il.invoiceid,
                                          il.trackid,
                                          il.unitprice,
                                          il.quantity,
                                          sum(il.unitprice * il.quantity) as line_total        
                                   from stg.invoiceline as il
                                   group by il.invoicelineid,
                                            il.invoiceid,
                                            il.trackid,
                                            il.unitprice,
                                            il.quantity
);


------ Transfering all the tables we created from stg to dwh 
DO $$ 
DECLARE
    rec RECORD;
BEGIN
    -- חפש את כל הטבלאות בסכימה stg
    FOR rec IN 
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = 'stg'  -- החלף בשם הסכמה שלך אם צריך
    LOOP
        -- עבור כל טבלה, העבר אותה לסכמה החדשה dwh
        EXECUTE 'ALTER TABLE stg.' || rec.table_name || ' SET SCHEMA dwh';
    END LOOP;
END $$;


ALTER TABLE stg."dim_currency" SET SCHEMA dwh;



--- SQL DATA ANALYSIS Q1.

WITH playlist_counts AS (
    SELECT 
        playlistid,
        COUNT(trackid) AS total_tracks
    FROM dwh.dim_playlist
    GROUP BY playlistid
),
playlist_with_stats AS (
    SELECT 
        playlistid,
        total_tracks,
        MAX(total_tracks) OVER () AS max_tracks,
        MIN(total_tracks) OVER () AS min_tracks,
        AVG(total_tracks) OVER () AS avg_tracks
    FROM playlist_counts
)
SELECT 
    CASE 
        WHEN total_tracks = max_tracks THEN 'Max Tracks'
        WHEN total_tracks = min_tracks THEN 'Min Tracks'
    END AS playlist_type,
    playlistid,
    total_tracks,
    avg_tracks
FROM playlist_with_stats
WHERE total_tracks = max_tracks
   OR total_tracks = min_tracks
ORDER BY playlist_type, playlistid;




--- SQL DATA ANALYSIS Q2.


WITH track_sales_count AS (
    SELECT
        trackid,
        COUNT(*) AS sales_count
    FROM dwh.fact_invoiceline
    GROUP BY trackid
)

SELECT 
    CASE 
        WHEN sales_count > 10 THEN '10<'
        WHEN sales_count BETWEEN 5 AND 10 THEN '5-10'
        WHEN sales_count BETWEEN 1 AND 5 THEN '1-5'
        WHEN sales_count = 0 THEN '0'
    END AS sales_group,
    COUNT(*) AS num_of_tracks
FROM track_sales_count
GROUP BY sales_group
ORDER BY sales_group;






---SQL DATA ANALYSIS Q3a.

select * from dwh.dim_customer dc; 
select * from dwh.dim_employee de;
select * from dwh.dim_playlist dp;
select * from dwh.dim_track dt;
select * from dwh.fact_invoice fi;
select * from dwh.fact_invoiceline fil;
select * from dwh.dim_currency dc;


with sum_sales_per_country as (
    select
        dc.country,
        sum(fi.total) as total_sales
    from
        dwh.dim_customer dc
        join dwh.fact_invoice fi on dc.customerid = fi.customerid
    group by
        dc.country
),
top_5_countries as (
    select
        country,
        total_sales
    from
        sum_sales_per_country
    order by
        total_sales desc
    limit 5
),
bottom_5_countries as (
    select
        country,
        total_sales
    from
        sum_sales_per_country
    order by
        total_sales asc
    limit 5
),
selected_countries as (
    select * from top_5_countries
    union all
    select * from bottom_5_countries
)

select
    country,
    total_sales
from
    selected_countries
order by
    total_sales desc;





--sql data analysis q3b.

with sum_sales_per_country as (
    select
        dc.country,
        sum(fi.total) as total_sales
    from
        dwh.dim_customer dc
        join dwh.fact_invoice fi on dc.customerid = fi.customerid
    group by
        dc.country
),
top_5_countries as (
    select
        country
    from
        sum_sales_per_country
    order by
        total_sales desc
    limit 5
),
bottom_5_countries as (
    select
        country
    from
        sum_sales_per_country
    order by
        total_sales asc
    limit 5
),
selected_countries as (
    select * from top_5_countries
    union all
    select * from bottom_5_countries
),
genre_sales_per_country as (
    select
        dc.country,
        dt.genre_name,
        sum(fil.unitprice * fil.quantity) as genre_sales
    from
        dwh.dim_customer dc
        join dwh.fact_invoice fi on dc.customerid = fi.customerid
        join dwh.fact_invoiceline fil on fi.invoiceid = fil.invoiceid
        join dwh.dim_track dt on fil.trackid = dt.trackid
    where
        dc.country in (select country from selected_countries)
    group by
        dc.country, dt.genre_name
)

select
    gspc.country,
    gspc.genre_name,
    gspc.genre_sales,
    spc.total_sales,
    round(100.0 * gspc.genre_sales / spc.total_sales, 2) as genre_percentage,
    rank() over (
        partition by gspc.country
        order by (100.0 * gspc.genre_sales / spc.total_sales) desc
    ) as genre_rank_in_country
from
    genre_sales_per_country gspc
    join sum_sales_per_country spc on gspc.country = spc.country
where
    gspc.country in (select country from selected_countries)
order by
    gspc.country,
    genre_rank_in_country;



---sql data analysis q4.


with customer_summary as (
                           select
                                  dc.country,
                                  count(distinct dc.customerid) as num_customers,
                                  count(fi.invoiceid) as total_invoices,
                                  sum(fi.total) as total_revenue
                           from dwh.dim_customer dc
                           left join dwh.fact_invoice fi on dc.customerid = fi.customerid
                           group by dc.country
                        ),
customer_with_group as (
                          select
                                 case when num_customers = 1 then 'Other' else country end as country_group,
                                 num_customers,
                                 total_invoices,
                                 total_revenue
                          from customer_summary
                       ),
country_grouped as (
                     select
                            country_group,
                            sum(num_customers) as total_customers,
                            sum(total_invoices) as total_invoices,
                            sum(total_revenue) as total_revenue
                     from customer_with_group
                     group by country_group
                   )

select
    country_group,
    total_customers,
    round(total_invoices * 1.0 / total_customers, 2) as avg_invoices_per_customer,
    round(total_revenue / total_customers, 2) as avg_revenue_per_customer
from
    country_grouped
order by
    case when country_group = 'Other' then 2 else 1 end,
    total_customers desc;



--sql data analysis q5.

with employee_base as (
                        select
                               de.employeeid,
                               de.firstname || ' ' || de.lastname as employee_name,
                               extract(year from de.hiredate) as hire_year,
                               extract(year from current_date) - extract(year from de.hiredate) as seniority_years
                        from dwh.dim_employee de
                      ),

sales_per_employee_per_year as (
                                 select
                                        de.employeeid,
                                        extract(year from fi.invoicedate) as sale_year,
                                        count(distinct fi.customerid) as customers_handled,
                                        sum(fi.total) as total_sales
                                 from dwh.fact_invoice fi
                                 join dwh.dim_customer dc on fi.customerid = dc.customerid
                                 join dwh.dim_employee de on dc.supportrepid = de.employeeid
                                 group by de.employeeid,
                                          extract(year from fi.invoicedate)
                               ),

growth_calculation as (
                        select
                               spe.employeeid,
                               spe.sale_year,
                               spe.customers_handled,
                               spe.total_sales,
                               lag(spe.total_sales) over (partition by spe.employeeid order by spe.sale_year) as previous_year_sales
                        from sales_per_employee_per_year spe
                      )

select
       eb.employeeid,
       eb.employee_name,
       eb.hire_year,
       eb.seniority_years,
       gc.sale_year,
       gc.customers_handled,
       gc.total_sales,
       case 
         when gc.previous_year_sales is null then 0
         when gc.previous_year_sales = 0 then 0
         else round(100.0 * (gc.total_sales - gc.previous_year_sales) / gc.previous_year_sales, 2)
       end as sales_growth_percentage
from growth_calculation gc
join employee_base eb on gc.employeeid = eb.employeeid
order by
         eb.employeeid,
         gc.sale_year;



--- extra sql analysis that shows the top 5 countries with the most revenue per customer in order to:
--- 1. check for opportunities to preserve and invest in the top 5 countries
--- 2. characterization of quality target audience
--- 3. comparison to weaker countries sales wise
--- 4. check which countries is ideal for market expansions 

SELECT 
    dc.Country,
    COUNT(DISTINCT dc.CustomerId) AS Num_Customers,
    COUNT(fi.InvoiceId) AS Num_Invoices,
    SUM(fi.Total) AS Total_Revenue,
    SUM(fi.Total) / COUNT(DISTINCT dc.CustomerId) AS Revenue_Per_Customer,
    AVG(fi.Total) AS Avg_Invoice_Amount
FROM 
    Dim_customer AS dc 
JOIN 
    fact_invoice AS fi ON dc.customerid = fi.customerid
GROUP BY 
    dc.Country
ORDER BY 
    Revenue_Per_Customer DESC
LIMIT 5;
