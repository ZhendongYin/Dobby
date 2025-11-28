import Chart from "chart.js/auto"

export const CampaignChart = {
  mounted() {
    const ctx = this.el.getContext("2d")
    const type = this.el.dataset.type || "line"
    const series = JSON.parse(this.el.dataset.series || "{}")

    this.chart = new Chart(ctx, {
      type,
      data: series,
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            display: true,
            position: "bottom"
          }
        }
      }
    })
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy()
    }
  }
}

