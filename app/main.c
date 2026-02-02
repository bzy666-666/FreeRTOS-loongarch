/* main.c */
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "semphr.h"

/* ================= 外部依赖 ================= */
extern void uart_init(void);
extern void uart_puts(char *s);

/* ================= 全局句柄 ================= */
/* 队列句柄：用于在任务间传递整数 */
QueueHandle_t xIntegerQueue;
/* 二值信号量句柄：用于同步事件 */
SemaphoreHandle_t xBinarySemaphore;
/* 互斥锁句柄：用于保护串口不冲突 */
SemaphoreHandle_t xUartMutex;

/* ================= 辅助函数 ================= */

/* 如果报错找不到 memset/memcpy，保留这两个 */
void *memset(void *s, int c, size_t n) {
    unsigned char *p = s;
    while (n--) *p++ = c;
    return s;
}

void *memcpy(void *dest, const void *src, size_t n) {
    char *d = dest;
    const char *s = src;
    while (n--) *d++ = *s++;
    return dest;
}

/* 简单的整数转字符串函数 (避免引入庞大的 printf) */
void int_to_str(int value, char *str) {
    char temp[16];
    int i = 0;
    int sign = 0;
    
    if (value < 0) {
        sign = 1;
        value = -value;
    }
    
    if (value == 0) {
        str[0] = '0';
        str[1] = '\0';
        return;
    }

    while (value > 0) {
        temp[i++] = (value % 10) + '0';
        value /= 10;
    }
    if (sign) temp[i++] = '-';
    
    int j = 0;
    while (i > 0) {
        str[j++] = temp[--i];
    }
    str[j] = '\0';
}

/* 线程安全的串口打印函数 (使用 Mutex 保护) */
void uart_print(const char* msg) {
    /* 如果调度器还没开始，或者互斥锁没创建，直接打印 */
    if (xTaskGetSchedulerState() != taskSCHEDULER_RUNNING || xUartMutex == NULL) {
        uart_puts((char*)msg);
    } else {
        /* 获取锁：如果别人在用，我就等 */
        xSemaphoreTake(xUartMutex, portMAX_DELAY);
        uart_puts((char*)msg);
        /* 释放锁 */
        xSemaphoreGive(xUartMutex);
    }
}

/* ================= 任务定义 ================= */

/* 任务1：普通的周期性打印任务 */
void vTaskBlink(void *pvParameters) {
    const char *pcTaskName = (const char *)pvParameters;
    for (;;) {
        uart_print(pcTaskName);
        uart_print(" is alive (1s cycle)\r\n");
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}

/* 任务2：队列发送者 (Producer) */
void vSenderTask(void *pvParameters) {
    int32_t lValueToSend = 0;
    char numBuf[16];

    for (;;) {
        /* 每 2 秒发送一次数据 */
        vTaskDelay(pdMS_TO_TICKS(2000));
        
        lValueToSend++;
        
        uart_print("[Sender] Sending: ");
        int_to_str(lValueToSend, numBuf);
        uart_print(numBuf);
        uart_print("\r\n");

        /* 发送数据到队列，如果队列满则等待 0 Tick */
        xQueueSend(xIntegerQueue, &lValueToSend, 0);
    }
}

/* 任务3：队列接收者 (Consumer) */
void vReceiverTask(void *pvParameters) {
    int32_t lReceivedValue;
    char numBuf[16];
    BaseType_t xStatus;

    for (;;) {
        /* 死等数据 (portMAX_DELAY)：只要队列没数据，我就睡觉，不占 CPU */
        xStatus = xQueueReceive(xIntegerQueue, &lReceivedValue, portMAX_DELAY);

        if (xStatus == pdPASS) {
            uart_print("    [Receiver] Got: ");
            int_to_str(lReceivedValue, numBuf);
            uart_print(numBuf);
            uart_print("\r\n");
        }
    }
}

/* 任务4：信号量释放者 (Trigger) */
void vSemGiveTask(void *pvParameters) {
    for (;;) {
        /* 每 3 秒触发一次事件 */
        vTaskDelay(pdMS_TO_TICKS(3000));
        uart_print("[Trigger] Firing Event!\r\n");
        xSemaphoreGive(xBinarySemaphore);
    }
}

/* 任务5：信号量处理者 (Handler) */
void vSemTakeTask(void *pvParameters) {
    for (;;) {
        /* 等待信号量：平时阻塞，一旦 GiveTask 释放，这里立马醒来 */
        if (xSemaphoreTake(xBinarySemaphore, portMAX_DELAY) == pdTRUE) {
            uart_print("    [Handler] Event Processed!\r\n");
        }
    }
}

/* ================= Main ================= */
int main(void) {
    /* 1. 初始化硬件 */
    uart_init();
    uart_print("\r\n=== LoongArch64 FreeRTOS Comprehensive Test ===\r\n");

    /* 2. 创建 IPC 对象 */
    
    /* 创建一个深度为 5，每个单元大小为 sizeof(int32_t) 的队列 */
    xIntegerQueue = xQueueCreate(5, sizeof(int32_t));
    
    /* 创建二值信号量 */
    xBinarySemaphore = xSemaphoreCreateBinary();
    
    /* 创建互斥锁 */
    xUartMutex = xSemaphoreCreateMutex();

    if (xIntegerQueue != NULL && xBinarySemaphore != NULL && xUartMutex != NULL) {
        
        /* 3. 创建任务 */
        
        /* 基础心跳任务 (优先级 1) */
        xTaskCreate(vTaskBlink, "Blink", 1024, "Task1", 1, NULL);

        /* 队列测试任务 (优先级 2) */
        xTaskCreate(vSenderTask, "Sender", 1024, NULL, 2, NULL);
        xTaskCreate(vReceiverTask, "Receiver", 1024, NULL, 2, NULL);

        /* 信号量测试任务 (优先级 3 - 更高) */
        xTaskCreate(vSemGiveTask, "SemGive", 1024, NULL, 3, NULL);
        xTaskCreate(vSemTakeTask, "SemTake", 1024, NULL, 3, NULL);

        /* 4. 启动调度器 */
        uart_print("Starting Scheduler...\r\n");
        vTaskStartScheduler();
    } else {
        uart_print("Error: Failed to create IPC objects (Heap too small?)\r\n");
    }

    /* 永远不应该运行到这里 */
    for(;;);
    return 0;
}
