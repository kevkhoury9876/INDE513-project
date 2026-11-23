# Naggiar Production Database: INDE 513 website

A Flask website connected to our Chapter 7 SQLite database (Naggiar injection
and blow molding plant). Users can **view**, **search** and **add** records.

## Files

| File | What it does |
|---|---|
| `app.py` | The whole Flask app: database connection, pages, forms, rules |
| `database.sql` | Chapter 7 Parts A and B (tables, indexes, triggers, sample data) |
| `templates/` | HTML pages (Jinja templates); `base.html` holds the menu |
| `static/style.css` | The page design |
| `requirements.txt` | Python packages: Flask and gunicorn |
| `render.yaml` | Settings for putting the site online with Render |

`naggiar.db` is **not** included: the app builds it from `database.sql` the
first time it starts. "Reset demo data" (bottom of every page) rebuilds it.

## Run it on your laptop

1. Install Python 3.10 or newer.
2. Open a terminal in this folder and run:
   ```
   pip install flask
   python app.py
   ```
3. Open http://127.0.0.1:5000 in your browser. Stop it with Ctrl+C.

## Put it online with Render (free)

1. Create a GitHub repository and upload every file in this folder.
2. On https://render.com sign in with GitHub, then **New > Web Service** and pick the repository.
3. Settings (Render fills most from `render.yaml`):
   - Runtime: **Python**
   - Build command: `pip install -r requirements.txt`
   - Start command: `gunicorn app:app`
   - Instance type: **Free**
4. Click **Create Web Service**. After a few minutes you get a link like
   `https://naggiar-production-db.onrender.com`.

Note: on the free plan the disk is temporary. Records you add disappear when
the service restarts or redeploys, and the site goes back to the sample data.
That is fine for a class demo. The free site also sleeps after 15 minutes
without visitors, so the first visit can take about a minute.

## Features

| Page | View / search / add | Database ideas it shows |
|---|---|---|
| Dashboard | View | Q5 (LEFT JOIN + GROUP BY), cell limits from the triggers |
| Machines | Search by text, type, status, cell; detail page | MachineMold (M:N), weak-entity run history |
| Production runs | Search by status, machine, dates, product; **add a run** | Weak entity runNo, WorksOn (M:N), transaction |
| Material lots | Search; **receive a new lot** | Q6 remaining stock, CHECK and UNIQUE rules |
| Suppliers | Search by name, email, address, material | Multivalued attributes (phones, addresses) |
| Traceability | Product to lots, or lot to products | Q10 (7-table join), Q9 recursive UsesPreform |
| Reports | The 12 Chapter 7 queries, run live with their SQL | Part C |

### Rules checked when adding records

Schedule a run:
- Only machine and mold pairs listed in MachineMold, with both in service.
- `runNo` is the machine's last run number + 1 (weak entity).
- No overlap with another run on the same machine.
- Every operator must be certified for the machine's molding type (same idea as Q12).
- The run and its operators are saved in one transaction: both are saved, or neither is.

Receive a lot:
- The supplier must be a listed source of that material (MaterialSupplier).
- Materials used in food-contact products need a compliance document.
- The database's own rules then test the rest: lot number letters and digits only,
  unique lot number, date format, quantities and cost above zero. If one fails,
  the page shows the database's message instead of crashing.

Foreign keys are switched on (`PRAGMA foreign_keys = ON`) for every connection,
as in Chapter 7.

## Tools and how AI helped (for the report)

We built the site with Python, Flask (web framework), SQLite (our Chapter 7
database), Jinja templates and CSS, and put it online with Render. We used an
AI assistant (Claude) to write the first version of the Flask code and page
templates from our Chapter 7 SQL file, to turn our Chapter 7 queries into
search pages and reports, and to suggest checks for the forms based on our
business rules. We then tested every page and form ourselves, including
inputs that should be refused, and checked the results against our queries.
