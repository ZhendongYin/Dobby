// Scratch Card Hook for Phoenix LiveView
export const ScratchCard = {
  mounted() {
    // 初始化状态变量
    this.isScratching = false;
    this.scratchedPixels = 0;
    this.totalPixels = 0;
    this.lastProgress = 0;
    this.lastProgressCheck = 0;
    this.revealed = false;
    this.canvas = null;
    this.ctx = null;

    // 延迟初始化，确保元素尺寸已经计算
    setTimeout(() => {
      this.canvas = this.el.querySelector("canvas");
      if (!this.canvas) {
        this.canvas = document.createElement("canvas");
        this.canvas.style.position = "absolute";
        this.canvas.style.top = "0";
        this.canvas.style.left = "0";
        this.canvas.style.width = "100%";
        this.canvas.style.height = "100%";
        this.canvas.style.zIndex = "999";
        this.canvas.style.pointerEvents = "auto";
        this.canvas.style.backgroundColor = "transparent";
        this.el.appendChild(this.canvas);
      }

      // 确保 canvas 有正确的尺寸
      const width = this.el.offsetWidth || 400;
      const height = this.el.offsetHeight || 288;
      
      // 设置 canvas 的实际像素尺寸（不是 CSS 尺寸）
      // 注意：canvas.width 和 canvas.height 是实际像素数，而 style.width/height 是 CSS 尺寸
      this.canvas.width = width;
      this.canvas.height = height;
      this.totalPixels = width * height;

      this.ctx = this.canvas.getContext("2d");
      
      // 初始化 Canvas：绘制灰色涂层
      this.initCanvas();
      
      // Canvas 初始化完成后，隐藏备用灰色涂层
      const backupOverlay = this.el.querySelector("#scratch-overlay-backup");
      if (backupOverlay) {
        backupOverlay.style.display = "none";
      }
      
    }, 100);

    // Mouse events
    this.el.addEventListener("mousedown", (e) => this.startScratch(e));
    this.el.addEventListener("mousemove", (e) => this.scratch(e));
    this.el.addEventListener("mouseup", () => this.stopScratch());
    this.el.addEventListener("mouseleave", () => this.stopScratch());

    // Touch events
    this.el.addEventListener("touchstart", (e) => {
      e.preventDefault();
      this.startScratch(e.touches[0]);
    });
    this.el.addEventListener("touchmove", (e) => {
      e.preventDefault();
      this.scratch(e.touches[0]);
    });
    this.el.addEventListener("touchend", () => this.stopScratch());
  },

  initCanvas() {
    if (!this.ctx || !this.canvas) {
      console.error("Canvas or context not initialized");
      return;
    }
    
    // 确保 canvas 尺寸正确
    if (this.canvas.width === 0 || this.canvas.height === 0) {
      this.canvas.width = this.el.offsetWidth || 400;
      this.canvas.height = this.el.offsetHeight || 288;
    }
    this.totalPixels = this.canvas.width * this.canvas.height;
    
    // 清除 canvas（这会清除所有内容，包括之前的绘制）
    this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    
    // 先设置正常绘制模式，绘制灰色涂层
    // 注意：必须使用 source-over 模式来绘制初始涂层
    this.ctx.globalCompositeOperation = "source-over";
    this.ctx.fillStyle = "#9CA3AF";
    this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
    
    // 然后设置擦除模式，用于刮开时擦除涂层
    // destination-out 模式：新绘制的内容会擦除已存在的内容（透明化）
    // 注意：这个设置会一直保持，直到下次调用 initCanvas
    this.ctx.globalCompositeOperation = "destination-out";
    this.ctx.globalAlpha = 1.0;
    
    console.log("Canvas initialized with gray overlay", {
      width: this.canvas.width,
      height: this.canvas.height,
      totalPixels: this.totalPixels,
      compositeOperation: this.ctx.globalCompositeOperation,
      canvasVisible: this.canvas.style.display !== "none"
    });
  },

  startScratch(e) {
    if (!this.ctx || !this.canvas) {
      console.warn("Canvas not ready for scratching");
      return;
    }
    
    // 确保 Canvas 仍然存在且可见
    if (!this.canvas.parentNode) {
      console.error("Canvas was removed from DOM!");
      return;
    }
    
    this.isScratching = true;
    const rect = this.el.getBoundingClientRect();
    this.lastX = e.clientX - rect.left;
    this.lastY = e.clientY - rect.top;
    
    // 立即绘制一个点，确保第一次点击也能擦除
    const scaleX = this.canvas.width / rect.width;
    const scaleY = this.canvas.height / rect.height;
    const canvasX = this.lastX * scaleX;
    const canvasY = this.lastY * scaleY;
    
    // 验证坐标是否在有效范围内
    if (canvasX < 0 || canvasX > this.canvas.width || canvasY < 0 || canvasY > this.canvas.height) {
      console.warn("Invalid coordinates:", { canvasX, canvasY, width: this.canvas.width, height: this.canvas.height });
      return;
    }
    
    // 确保在 destination-out 模式下绘制
    // 只擦除一个小点，不要擦除整个 canvas
    this.ctx.globalCompositeOperation = "destination-out";
    this.ctx.beginPath();
    this.ctx.arc(canvasX, canvasY, 15, 0, Math.PI * 2);
    this.ctx.fill();
    
    console.log("Start scratch at:", { 
      canvasX: Math.round(canvasX), 
      canvasY: Math.round(canvasY), 
      scaleX: scaleX.toFixed(2), 
      scaleY: scaleY.toFixed(2), 
      lastX: Math.round(this.lastX), 
      lastY: Math.round(this.lastY),
      canvasSize: `${this.canvas.width}x${this.canvas.height}`,
      rectSize: `${rect.width}x${rect.height}`
    });
  },

  scratch(e) {
    if (!this.isScratching || this.revealed || !this.ctx || !this.canvas) return;
    
    // 确保 Canvas 仍然存在
    if (!this.canvas.parentNode) {
      console.error("Canvas was removed from DOM during scratch!");
      this.isScratching = false;
      return;
    }

    const rect = this.el.getBoundingClientRect();
    const scaleX = this.canvas.width / rect.width;
    const scaleY = this.canvas.height / rect.height;
    
    // 将鼠标/触摸坐标转换为 canvas 坐标
    const relX = e.clientX - rect.left;
    const relY = e.clientY - rect.top;
    const currentX = relX * scaleX;
    const currentY = relY * scaleY;
    
    // 计算上一次的 canvas 坐标
    const lastCanvasX = this.lastX * scaleX;
    const lastCanvasY = this.lastY * scaleY;
    
    // 验证坐标是否在有效范围内
    if (isNaN(currentX) || isNaN(currentY) || isNaN(lastCanvasX) || isNaN(lastCanvasY)) {
      console.warn("Invalid coordinates detected:", { currentX, currentY, lastCanvasX, lastCanvasY });
      return;
    }

    // 确保在 destination-out 模式下绘制
    this.ctx.globalCompositeOperation = "destination-out";
    
    // 使用较小的画笔，确保是逐步刮开
    // destination-out 模式：绘制的内容会擦除灰色涂层，露出下面的奖品信息
    this.ctx.beginPath();
    this.ctx.lineWidth = 30;
    this.ctx.lineCap = "round";
    this.ctx.lineJoin = "round";
    this.ctx.moveTo(lastCanvasX, lastCanvasY);
    this.ctx.lineTo(currentX, currentY);
    this.ctx.stroke();

    // 更新 lastX 和 lastY（使用相对坐标，用于下次计算）
    this.lastX = relX;
    this.lastY = relY;

    // Throttle progress calculation to avoid too frequent updates
    if (!this.lastProgressCheck || Date.now() - this.lastProgressCheck > 100) {
      // Calculate scratched percentage
      const imageData = this.ctx.getImageData(0, 0, this.canvas.width, this.canvas.height);
      let transparentPixels = 0;
      for (let i = 3; i < imageData.data.length; i += 4) {
        if (imageData.data[i] === 0) {
          transparentPixels++;
        }
      }

      const progress = transparentPixels / this.totalPixels;
      
      // Only push event if progress changed significantly (throttle)
      if (!this.lastProgress || Math.abs(progress - this.lastProgress) > 0.02) {
        this.pushEvent("update_progress", { progress: progress });
        this.lastProgress = progress;
      }

      // Auto-reveal if 50% scratched (with a small buffer to ensure it's really 50%)
      if (progress >= 0.5 && !this.revealed) {
        this.reveal();
      }

      this.lastProgressCheck = Date.now();
    }
  },

  stopScratch() {
    this.isScratching = false;
  },

  reveal() {
    this.revealed = true;
    // 不要清除 canvas，保持刮开的效果
    // 只是确保进度达到 100%
    this.pushEvent("update_progress", { progress: 1.0 });
  },

  updated() {
    // 检查 Canvas 是否还在 DOM 中，如果不在则重新创建
    if (!this.canvas || !this.canvas.parentNode) {
      console.log("Canvas was removed, recreating...");
      // 重新创建 Canvas
      this.canvas = document.createElement("canvas");
      this.canvas.style.position = "absolute";
      this.canvas.style.top = "0";
      this.canvas.style.left = "0";
      this.canvas.style.width = "100%";
      this.canvas.style.height = "100%";
      this.canvas.style.zIndex = "999";
      this.canvas.style.pointerEvents = "auto";
      this.canvas.style.backgroundColor = "transparent";
      this.el.appendChild(this.canvas);
      
      // 重新初始化
      const width = this.el.offsetWidth || 400;
      const height = this.el.offsetHeight || 288;
      this.canvas.width = width;
      this.canvas.height = height;
      this.totalPixels = width * height;
      this.ctx = this.canvas.getContext("2d");
      
      // 如果已经刮开，不要重新绘制涂层
      if (!this.revealed) {
        this.initCanvas();
      }
      
      // Canvas 重新创建后，隐藏备用灰色涂层
      const backupOverlay = this.el.querySelector("#scratch-overlay-backup");
      if (backupOverlay) {
        backupOverlay.style.display = "none";
      }
      return;
    }
    
    // Resize canvas if needed
    const newWidth = this.el.offsetWidth || 400;
    const newHeight = this.el.offsetHeight || 288;
    
    if (this.canvas.width !== newWidth || this.canvas.height !== newHeight) {
      this.canvas.width = newWidth;
      this.canvas.height = newHeight;
      
      // 只有在未刮开时才重新填充涂层
      if (!this.revealed) {
        this.initCanvas();
      } else {
        this.totalPixels = this.canvas.width * this.canvas.height;
      }
    }
  }
};

