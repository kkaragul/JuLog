<template>
  <div class="solver-container">
    <h1>MSHH Solver</h1>
    <p class="subtitle">Multi-Stage Selection Hyper-Heuristic Framework</p>

    <div class="solver-panel">
      <!-- Domain Selection -->
      <div class="section">
        <h2>Problem Domain</h2>
        <div class="radio-group">
          <label>
            <input type="radio" value="tsp" v-model="selectedDomain" />
            <span>TSP (Traveling Salesman Problem)</span>
          </label>
          <label>
            <input type="radio" value="cvrp" v-model="selectedDomain" />
            <span>CVRP (Capacitated Vehicle Routing)</span>
          </label>
        </div>
      </div>

      <!-- Instance Selection -->
      <div class="section">
        <h2>Instance</h2>
        <select v-model="selectedInstance" class="instance-select">
          <option value="">Select instance...</option>
          <option
            v-for="instance in availableInstances"
            :key="instance"
            :value="instance"
          >
            {{ instance }}
          </option>
        </select>

        <div class="upload-section">
          <label class="upload-btn">
            <input
              type="file"
              @change="handleFileUpload"
              :accept="selectedDomain === 'tsp' ? '.tsp' : '.vrp'"
              style="display: none"
            />
            <span>📁 Upload Instance</span>
          </label>
          <span v-if="uploadedFile" class="uploaded-file">
            ✓ {{ uploadedFile.name }}
          </span>
        </div>
      </div>

      <!-- Parameters -->
      <div class="section">
        <h2>Parameters</h2>
        <div class="param-grid">
          <div class="param">
            <label>Time Limit (seconds)</label>
            <input type="number" v-model.number="timeLimit" min="1" />
          </div>
          <div class="param">
            <label>τ (Heuristic Duration ms)</label>
            <input
              type="number"
              v-model.number="parameters.tau"
              min="0.001"
              step="0.001"
            />
          </div>
          <div class="param">
            <label>d (Epsilon Update s)</label>
            <input
              type="number"
              v-model.number="parameters.d"
              min="1"
              step="1"
            />
          </div>
          <div class="param">
            <label>s1 (Stage 1 Duration s)</label>
            <input
              type="number"
              v-model.number="parameters.s1"
              min="1"
              step="1"
            />
          </div>
          <div class="param">
            <label>s2 (Stage 2 Steps)</label>
            <input
              type="number"
              v-model.number="parameters.s2"
              min="1"
              step="1"
            />
          </div>
          <div class="param">
            <label>P<sub>S2HH</sub> (Stage 2 Probability)</label>
            <input
              type="number"
              v-model.number="parameters.PS2HH"
              min="0"
              max="1"
              step="0.1"
            />
          </div>
        </div>
      </div>

      <!-- Solve Button -->
      <div class="section">
        <button
          class="solve-btn"
          @click="solve"
          :disabled="!canSolve || solving"
        >
          {{ solving ? "Solving..." : "🚀 Solve" }}
        </button>
      </div>

      <!-- Progress -->
      <div v-if="solving" class="section progress-section">
        <h2>Progress</h2>
        <div class="progress-bar">
          <div class="progress-fill" :style="{ width: progress + '%' }"></div>
        </div>
        <p class="status-text">{{ statusText }}</p>
      </div>

      <!-- Results -->
      <div v-if="result" class="section results-section">
        <h2>Results</h2>
        <div class="result-grid">
          <div class="result-item">
            <span class="label">Best Objective:</span>
            <span class="value">{{ result.best_objective.toFixed(2) }}</span>
          </div>
          <div class="result-item">
            <span class="label">Computation Time:</span>
            <span class="value">{{ result.computation_time.toFixed(2) }}s</span>
          </div>
          <div class="result-item">
            <span class="label">Stages Executed:</span>
            <span class="value">{{ result.stages_executed }}</span>
          </div>
          <div class="result-item">
            <span class="label">S1HH Executions:</span>
            <span class="value">{{ result.s1hh_executions || "N/A" }}</span>
          </div>
          <div class="result-item">
            <span class="label">S2HH Executions:</span>
            <span class="value">{{ result.s2hh_executions || "N/A" }}</span>
          </div>
        </div>

        <!-- Visualizer Component (placeholder for Session 1) -->
        <div class="visualization">
          <h3>Solution Visualization</h3>
          <div v-if="selectedDomain === 'tsp' && result.tour" class="tour-info">
            <p>Tour: {{ result.tour.join(" → ") }}</p>
          </div>
          <div v-if="selectedDomain === 'cvrp' && result.routes" class="routes-info">
            <div v-for="(route, idx) in result.routes" :key="idx" class="route">
              <strong>Route {{ idx + 1 }}:</strong>
              Customers: {{ route.customers.join(", ") }} | Load:
              {{ route.load.toFixed(1) }}
            </div>
          </div>
        </div>
      </div>

      <!-- Error Display -->
      <div v-if="error" class="section error-section">
        <h2>Error</h2>
        <p class="error-text">{{ error }}</p>
      </div>
    </div>
  </div>
</template>

<script>
import {
  listInstances,
  solveTSP,
  solveCVRP,
  pollJobStatus,
  uploadInstance,
} from "../api/client.js";

export default {
  name: "Solver",
  data() {
    return {
      selectedDomain: "tsp",
      selectedInstance: "",
      availableInstances: [],
      uploadedFile: null,
      timeLimit: 60,
      parameters: {
        tau: 0.015,
        d: 9.0,
        s1: 20.0,
        s2: 5,
        PS2HH: 0.3,
      },
      solving: false,
      progress: 0,
      statusText: "",
      result: null,
      error: null,
    };
  },
  computed: {
    canSolve() {
      return this.selectedInstance || this.uploadedFile;
    },
  },
  watch: {
    selectedDomain() {
      this.loadInstances();
      this.selectedInstance = "";
    },
  },
  mounted() {
    this.loadInstances();
  },
  methods: {
    async loadInstances() {
      try {
        const instances = await listInstances();
        this.availableInstances = instances[this.selectedDomain] || [];
      } catch (err) {
        this.error = `Failed to load instances: ${err.message}`;
      }
    },

    async handleFileUpload(event) {
      const file = event.target.files[0];
      if (!file) return;

      try {
        const result = await uploadInstance(file, this.selectedDomain);
        this.uploadedFile = file;
        this.selectedInstance = result.filename;
        this.error = null;
      } catch (err) {
        this.error = `Failed to upload file: ${err.message}`;
      }
    },

    async solve() {
      if (!this.canSolve) return;

      this.solving = true;
      this.progress = 0;
      this.statusText = "Initializing...";
      this.result = null;
      this.error = null;

      try {
        // Get instance file path
        const instancePath = `instances/${this.selectedDomain}/${this.selectedInstance}`;

        // Start solving
        const solveFunc =
          this.selectedDomain === "tsp" ? solveTSP : solveCVRP;
        const jobResponse = await solveFunc(
          instancePath,
          this.timeLimit,
          this.parameters
        );

        this.statusText = "Solving...";

        // Poll for results
        const result = await pollJobStatus(
          jobResponse.job_id,
          (status) => {
            if (status.status === "running") {
              // Estimate progress (simple linear estimation)
              this.progress = Math.min(
                95,
                (Date.now() - startTime) / (this.timeLimit * 1000) * 100
              );
            }
          },
          1000
        );

        const startTime = Date.now();
        this.progress = 100;
        this.result = result;
        this.statusText = "Completed!";
      } catch (err) {
        this.error = `Solving failed: ${err.message}`;
      } finally {
        this.solving = false;
      }
    },
  },
};
</script>

<style scoped>
.solver-container {
  max-width: 1200px;
  margin: 0 auto;
  padding: 20px;
  font-family: "Segoe UI", Tahoma, Geneva, Verdana, sans-serif;
}

h1 {
  color: #2c3e50;
  margin-bottom: 5px;
}

.subtitle {
  color: #7f8c8d;
  margin-bottom: 30px;
}

.solver-panel {
  background: white;
  border-radius: 8px;
  box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1);
  padding: 30px;
}

.section {
  margin-bottom: 30px;
}

h2 {
  color: #34495e;
  font-size: 1.3em;
  margin-bottom: 15px;
  border-bottom: 2px solid #3498db;
  padding-bottom: 5px;
}

.radio-group {
  display: flex;
  gap: 20px;
}

.radio-group label {
  display: flex;
  align-items: center;
  gap: 8px;
  cursor: pointer;
}

.instance-select {
  width: 100%;
  padding: 10px;
  font-size: 1em;
  border: 2px solid #ddd;
  border-radius: 4px;
  margin-bottom: 15px;
}

.upload-section {
  display: flex;
  align-items: center;
  gap: 15px;
}

.upload-btn {
  display: inline-block;
  padding: 10px 20px;
  background: #95a5a6;
  color: white;
  border-radius: 4px;
  cursor: pointer;
  transition: background 0.3s;
}

.upload-btn:hover {
  background: #7f8c8d;
}

.uploaded-file {
  color: #27ae60;
  font-weight: bold;
}

.param-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 15px;
}

.param label {
  display: block;
  font-weight: bold;
  margin-bottom: 5px;
  color: #555;
}

.param input {
  width: 100%;
  padding: 8px;
  border: 2px solid #ddd;
  border-radius: 4px;
}

.solve-btn {
  width: 100%;
  padding: 15px;
  font-size: 1.2em;
  font-weight: bold;
  background: #3498db;
  color: white;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  transition: background 0.3s;
}

.solve-btn:hover:not(:disabled) {
  background: #2980b9;
}

.solve-btn:disabled {
  background: #bdc3c7;
  cursor: not-allowed;
}

.progress-section {
  background: #ecf0f1;
  padding: 20px;
  border-radius: 4px;
}

.progress-bar {
  width: 100%;
  height: 30px;
  background: #bdc3c7;
  border-radius: 15px;
  overflow: hidden;
  margin-bottom: 10px;
}

.progress-fill {
  height: 100%;
  background: linear-gradient(90deg, #3498db, #2ecc71);
  transition: width 0.3s;
}

.status-text {
  text-align: center;
  font-weight: bold;
  color: #2c3e50;
}

.results-section {
  background: #e8f8f5;
  padding: 20px;
  border-radius: 4px;
}

.result-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
  gap: 15px;
  margin-bottom: 20px;
}

.result-item {
  background: white;
  padding: 15px;
  border-radius: 4px;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
}

.result-item .label {
  display: block;
  font-weight: bold;
  color: #7f8c8d;
  margin-bottom: 5px;
}

.result-item .value {
  display: block;
  font-size: 1.5em;
  color: #2c3e50;
}

.visualization {
  background: white;
  padding: 20px;
  border-radius: 4px;
}

.tour-info,
.routes-info {
  padding: 10px;
  background: #ecf0f1;
  border-radius: 4px;
  font-family: monospace;
}

.route {
  padding: 8px;
  margin-bottom: 5px;
  background: white;
  border-left: 3px solid #3498db;
}

.error-section {
  background: #fadbd8;
  padding: 20px;
  border-radius: 4px;
}

.error-text {
  color: #c0392b;
  font-weight: bold;
}
</style>
