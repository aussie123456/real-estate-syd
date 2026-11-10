Optional school-quality overlay. Fill school_scores.csv and re-run build (perl scripts/build.pl).
Columns: school_name (exactly as named in NSW Spatial Services, upper case, e.g. EPPING BOYS HIGH SCHOOL),
         type (primary | high | combined | private), score (0-100, higher = better), note, source.
Suggested scoring (your call, keep it consistent):
  Public primary:  share of Year 4 cohort receiving Opportunity Class offers, or NAPLAN Year 5 vs state average.
  Public high:     HSC Band 6 rate / newspaper ranking (NESA merit lists are the primary source).
  Private:         enrolment demand (waitlist years, fee growth) scaled 0-100.
When a school has a score the dashboard switches the Schools component from "distance to nearest school"
to "score of the nearest school". Schools without a score fall back to distance.
Note: Better Education and newspaper league tables block scripted access, so this file is maintained by hand.

10 Nov 2026: high schools filled from the Matrix Education top-150 HSC success-rate tables, 2021-2025.
  Score = relative position by 5-year average rank (#1 = 100, last ranked = 0.5). A year outside the published list uses the
  prior-year rank shown in a later table where available, otherwise 200. Once any high school is ranked, build.pl scores
  every other secondary school 0 (outside the lists) instead of falling back to distance. Primary rows are still empty.
  Catchment rule (10 Nov 2026): the suburb score uses the nearest government high school you can attend by address
  (gov_schools.csv = NSW Education master dataset). Fully selective, private, audition-only (Conservatorium), distance-education
  and junior-only campuses are excluded; partially selective schools stay in because they keep a local intake.
