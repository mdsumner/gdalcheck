#!/usr/bin/env Rscript
# Generate HTML dashboard from check results

library(jsonlite)

args <- commandArgs(trailingOnly = TRUE)
results_dir <- if (length(args) >= 1) args[1] else "results"
output_dir <- if (length(args) >= 2) args[2] else "docs"

cat("=== Generating Dashboard ===\n")
cat(sprintf("Results: %s\n", results_dir))
cat(sprintf("Output: %s\n", output_dir))

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# Find most recent run
run_dirs <- list.dirs(results_dir, recursive = FALSE, full.names = TRUE)
run_dirs <- run_dirs[file.exists(file.path(run_dirs, "summary.json"))]

if (length(run_dirs) == 0) {
  cat("No results found, creating placeholder dashboard\n")
  writeLines("<!DOCTYPE html><html><body><h1>No results yet</h1></body></html>",
             file.path(output_dir, "index.html"))
  quit(status = 0)
}

# Sort by modification time, most recent first
run_times <- file.info(run_dirs)$mtime
run_dirs <- run_dirs[order(run_times, decreasing = TRUE)]

# Load current run
current_run <- basename(run_dirs[1])
summary <- fromJSON(file.path(run_dirs[1], "summary.json"))
all_results <- tryCatch(
  read.csv(file.path(run_dirs[1], "all_results.csv"), stringsAsFactors = FALSE),
  error = function(e) data.frame(package = character(), status = character())
)

cat(sprintf("Current run: %s\n", current_run))
cat(sprintf("Results: %d packages\n", nrow(all_results)))

# Build history from all runs
history <- lapply(run_dirs[1:min(30, length(run_dirs))], function(d) {
  s <- tryCatch(fromJSON(file.path(d, "summary.json")), error = function(e) NULL)
  if (is.null(s)) return(NULL)
  list(
    run_id = basename(d),
    completed_at = s$completed_at %||% "",
    total = s$total %||% 0,
    passed = s$passed %||% 0,
    failed = s$failed %||% 0
  )
})
history <- Filter(Negate(is.null), history)

# Prepare JSON for HTML
history_json <- toJSON(history, auto_unbox = TRUE)
all_results_json <- toJSON(all_results, auto_unbox = TRUE, dataframe = "rows")
failures_df <- all_results[all_results$status != "OK", , drop = FALSE]
failures_json <- toJSON(failures_df, auto_unbox = TRUE, dataframe = "rows")

gdal_version <- summary$gdal_version %||% "unknown"
pass_rate <- if (summary$total > 0) 100 * summary$passed / summary$total else 0

html <- sprintf('
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>gdalcheck - GDAL R Package Compatibility</title>
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
  <style>
    * { box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      margin: 0; padding: 20px;
      background: #f5f7fa;
      color: #333;
    }
    .container { max-width: 1200px; margin: 0 auto; }
    h1 { margin: 0 0 8px 0; color: #1a1a2e; }
    .subtitle { color: #666; margin-bottom: 24px; }
    
    .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 16px; margin-bottom: 24px; }
    .card {
      background: white; border-radius: 12px; padding: 20px;
      box-shadow: 0 1px 3px rgba(0,0,0,0.1);
    }
    .card-label { font-size: 13px; color: #666; text-transform: uppercase; letter-spacing: 0.5px; }
    .card-value { font-size: 32px; font-weight: 600; margin-top: 4px; }
    .card-value.success { color: #22c55e; }
    .card-value.danger { color: #ef4444; }
    .card-value.neutral { color: #3b82f6; }
    
    .panel {
      background: white; border-radius: 12px; padding: 20px;
      box-shadow: 0 1px 3px rgba(0,0,0,0.1); margin-bottom: 24px;
    }
    .panel h2 { margin: 0 0 16px 0; font-size: 18px; }
    
    .chart-container { height: 200px; }
    
    table { width: 100%%; border-collapse: collapse; }
    th, td { text-align: left; padding: 10px 12px; border-bottom: 1px solid #eee; }
    th { font-weight: 600; color: #666; font-size: 13px; text-transform: uppercase; }
    tr:hover { background: #f9fafb; }
    
    .status-badge {
      display: inline-block; padding: 3px 10px; border-radius: 12px;
      font-size: 12px; font-weight: 600;
    }
    .status-badge.ok { background: #dcfce7; color: #166534; }
    .status-badge.fail { background: #fee2e2; color: #991b1b; }
    
    .search-box {
      width: 100%%; padding: 10px 14px; border: 1px solid #ddd;
      border-radius: 8px; font-size: 14px; margin-bottom: 16px;
    }
    .search-box:focus { outline: none; border-color: #3b82f6; }
    
    .tabs { display: flex; gap: 8px; margin-bottom: 16px; }
    .tab {
      padding: 8px 16px; border-radius: 8px; cursor: pointer;
      border: 1px solid #ddd; background: white; font-size: 14px;
    }
    .tab.active { background: #3b82f6; color: white; border-color: #3b82f6; }
    
    .gdal-badge {
      display: inline-block; background: #1a1a2e; color: white;
      padding: 4px 12px; border-radius: 6px; font-size: 13px; font-weight: 500;
    }
    
    .timestamp { color: #888; font-size: 13px; }
    
    a { color: #3b82f6; text-decoration: none; }
    a:hover { text-decoration: underline; }
    
    @media (max-width: 600px) {
      .cards { grid-template-columns: 1fr 1fr; }
      .card-value { font-size: 24px; }
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>gdalcheck</h1>
    <p class="subtitle">
      <span class="gdal-badge">GDAL %s</span>
      <span class="timestamp">Run %s &bull; %s</span>
    </p>
    
    <div class="cards">
      <div class="card">
        <div class="card-label">Total Packages</div>
        <div class="card-value neutral">%d</div>
      </div>
      <div class="card">
        <div class="card-label">Passed</div>
        <div class="card-value success">%d</div>
      </div>
      <div class="card">
        <div class="card-label">Failed</div>
        <div class="card-value danger">%d</div>
      </div>
      <div class="card">
        <div class="card-label">Pass Rate</div>
        <div class="card-value neutral">%.1f%%%%</div>
      </div>
    </div>
    
    <div class="panel">
      <h2>History</h2>
      <div class="chart-container">
        <canvas id="historyChart"></canvas>
      </div>
    </div>
    
    <div class="panel">
      <h2>Results</h2>
      <div class="tabs">
        <div class="tab active" onclick="showTab(\'failures\')">Failures (%d)</div>
        <div class="tab" onclick="showTab(\'all\')">All Packages (%d)</div>
      </div>
      <input type="text" class="search-box" placeholder="Search packages..." oninput="filterTable(this.value)">
      <div id="failures-tab">
        <table id="failures-table">
          <thead><tr><th>Package</th><th>Status</th></tr></thead>
          <tbody></tbody>
        </table>
        <p id="no-failures" style="color: #22c55e; display: none;">All packages passed!</p>
      </div>
      <div id="all-tab" style="display: none;">
        <table id="all-table">
          <thead><tr><th>Package</th><th>Status</th></tr></thead>
          <tbody></tbody>
        </table>
      </div>
    </div>
    
    <p class="timestamp">
      Dashboard generated %s
      &bull; <a href="https://github.com/mdsumner/gdalcheck">Source</a>
    </p>
  </div>
  
  <script>
    const history = %s;
    const failures = %s;
    const allResults = %s;
    const runId = "%s";
    
    // Render history chart
    if (history.length > 0) {
      const ctx = document.getElementById("historyChart").getContext("2d");
      new Chart(ctx, {
        type: "line",
        data: {
          labels: history.map(r => r.run_id.slice(-8)),
          datasets: [
            {
              label: "Passed",
              data: history.map(r => r.passed),
              borderColor: "#22c55e",
              backgroundColor: "rgba(34, 197, 94, 0.1)",
              fill: true,
              tension: 0.3
            },
            {
              label: "Failed", 
              data: history.map(r => r.failed),
              borderColor: "#ef4444",
              backgroundColor: "rgba(239, 68, 68, 0.1)",
              fill: true,
              tension: 0.3
            }
          ]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: { legend: { position: "bottom" } },
          scales: { y: { beginAtZero: true } }
        }
      });
    }
    
    // Render tables
    function renderTable(tableId, data) {
      const tbody = document.querySelector(`#${tableId} tbody`);
      tbody.innerHTML = data.map(r => `
        <tr data-pkg="${r.package.toLowerCase()}">
          <td><a href="https://cran.r-project.org/package=${r.package}" target="_blank">${r.package}</a></td>
          <td><span class="status-badge ${r.status === "OK" ? "ok" : "fail"}">${r.status}</span></td>
        </tr>
      `).join("");
    }
    
    renderTable("failures-table", failures);
    renderTable("all-table", allResults);
    
    if (failures.length === 0) {
      document.getElementById("failures-table").style.display = "none";
      document.getElementById("no-failures").style.display = "block";
    }
    
    function showTab(tab) {
      document.querySelectorAll(".tab").forEach(t => t.classList.remove("active"));
      event.target.classList.add("active");
      document.getElementById("failures-tab").style.display = tab === "failures" ? "" : "none";
      document.getElementById("all-tab").style.display = tab === "all" ? "" : "none";
    }
    
    function filterTable(query) {
      const q = query.toLowerCase();
      document.querySelectorAll("tbody tr").forEach(row => {
        row.style.display = row.dataset.pkg.includes(q) ? "" : "none";
      });
    }
  </script>
</body>
</html>
',
  gdal_version,
  current_run,
  summary$completed_at %||% "",
  summary$total %||% 0,
  summary$passed %||% 0,
  summary$failed %||% 0,
  pass_rate,
  summary$failed %||% 0,
  summary$total %||% 0,
  format(Sys.time(), "%%Y-%%m-%%d %%H:%%M:%%S UTC"),
  history_json,
  failures_json,
  all_results_json,
  current_run
)

writeLines(html, file.path(output_dir, "index.html"))
cat(sprintf("Dashboard written to %s/index.html\n", output_dir))

# Also write history.json for reference
write_json(history, file.path(output_dir, "history.json"), pretty = TRUE)
