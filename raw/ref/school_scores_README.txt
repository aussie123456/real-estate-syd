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
