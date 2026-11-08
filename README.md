# Sydney Value Buys dashboard

Local, file-based screen for value in Sydney houses and land: land $/sqm by street and suburb,
distance to stations / CBD / schools / parks, crime, and each suburb's sensitivity to the RBA cash rate.
Everything runs from Git Bash (curl, perl, unzip) and the dashboard is a single HTML file.

## Folder
    raw/vg/        <- put Valuer General yearly zips here (2012.zip ... 2026.zip)  [you download these]
    raw/ref/       <- reference feeds fetched by scripts/fetch_ref.sh (RBA, ABS, BOCSAR, NSW Spatial)
                      school_scores.csv is yours to fill (see school_scores_README.txt)
    data/          <- sales.csv (parsed VG), geo.csv (property centroids, cached), geo_missing.txt
    dashboard/     <- index.html + data.js (built). Open index.html in Chrome/Edge.
    scripts/       <- fetch_ref.sh, parse_vg.sh (+ parse_vg.pl), geocode.sh, build.pl
    run_all.cmd    <- runs the four steps in order

## One-off: download the Valuer General sales files
The bulk files are free but the site blocks scripted downloads, so do this once in your browser:
1. Open https://valuation.property.nsw.gov.au/embed/propertySalesInformation
2. Choose "Yearly" and download each year you want (2012 to 2026 recommended for the rate analysis;
   2026 to date is in the yearly file too, or add the latest weekly files).
3. Save the zips into raw/vg/ with the year as the file name, e.g. raw/vg/2024.zip
4. Run run_all.cmd (first geocode pass takes ~30-60 min for ~400k properties; later runs only fetch new IDs).

## Refresh cadence
- VG publishes weekly (Monday). Drop the current year's new yearly zip over the old one and run run_all.cmd.
- RBA/ABS/BOCSAR/NSW Spatial feeds are refetched every run (fast).

## Method (short)
- Houses and vacant residential land only (strata / unit sales excluded). Land $/sqm = contract price / VG land area.
- Suburb figures are trailing-12-month medians from the latest contract date in the data.
- "Value" = residual of ln(suburb median $/sqm) against a quadratic in distance to Town Hall: negative = cheap for its ring.
- "Rates" = (a) drawdown of the 2-quarter smoothed median $/sqm from its 2021-22 peak and (b) beta of the
  2-quarter log change in that series on the 2-quarter change in the average cash rate, 2010Q1 onwards.
- Transport = distance to nearest train/metro station (60%) and to the CBD (40%); Parks = distance to nearest
  RE1 Public Recreation land >= 3,000 sqm; Safety = BOCSAR violent + property offences per 1,000 residents (2021 Census).
- Schools = score of nearest primary/high if you've filled school_scores.csv, otherwise distance to nearest.
- Each component is a Sydney-wide z-score (clipped +-2.5); the dashboard combines them with your weights.

## Run it on GitHub (Actions + Pages)
The same scripts run on an Ubuntu runner every week and publish the page to GitHub Pages, so nothing
depends on this laptop. One-off setup:
1. Create an empty GitHub repository (private is fine, Pages works on private repos for Pro/Team plans; otherwise public).
2. Push this folder:  git remote add origin <repo url>  then  git push -u origin main
3. Repository Settings > Pages > Source = "GitHub Actions".
4. Valuer General files: the workflow first tries to download each yearly zip directly. If the site refuses the
   runner too, upload the zips once as release assets: Releases > Draft a new release > tag "vg-data" > attach
   2012.zip ... 2026.zip (up to 2 GB each) > Publish. The workflow falls back to those automatically.
5. Actions > "Refresh dashboard" > Run workflow. The first run geocodes every property (about an hour); later runs
   only look up new ones because data/ is cached between runs. The step summary shows what loaded.
6. The page URL is shown on the deploy job (https://<user>.github.io/<repo>/). The "Refresh" chip in the header opens the
   workflow page for a manual re-run.
Schedule: Monday 18:00 UTC (Tuesday 5am Sydney), after the Valuer General's Monday release. Pushes to index.html or scripts also rebuild.
Workflow inputs: "years" to force re-loading specific years (e.g. 2012-2026); "regeocode" to rebuild the geocode cache.
Note: raw/, data/ and dashboard/data.js are git-ignored; nothing large is committed.

## Yield & returns tab (added 8 Nov 2026)
- Rent: NSW Fair Trading rental bond lodgements (every new bond, monthly xlsx) -> median weekly rent for houses (H) in the
  suburb's postcode over the trailing 12 months, plus 3-bed and 4-bed medians and unit rents. Needs 10+ bonds.
- Price and CAGRs: Valuer General suburb medians where loaded; otherwise the DCJ Rent and Sales Report "Sales tables by
  postcode" (non-strata median, 4-quarter average, quarterly history from June 2017). 10-year CAGR therefore needs VG data.
- Gross yield = rent x 52 / price. Net = gross x (1 - costs). ROE = (net + CAGR - LVR x rate) / (1 - LVR), first-year,
  pre tax/stamp duty. Cash ROE = same with zero growth. LVR, rate (defaults to the RBA investor discounted variable) and
  costs are inputs on the page.
- Suburbs sharing a postcode share rent and DCJ price figures; the Valuer General data is what makes them suburb-specific.
- The page degrades to tables if cdn.jsdelivr.net (Leaflet, Chart.js) or OpenStreetMap tiles are blocked.
