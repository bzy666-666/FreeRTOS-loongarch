#include "portmacro.h"

    .section .text
    .global xPortStartFirstTask           /* 启动第一个任务 */
    .global freertos_loongarch_trap_handler /* 唯一的异常入口 */
    
    .extern pxCurrentTCB
    .extern vTaskSwitchContext
    .extern xTaskIncrementTick

/* ================== 宏定义：保存上下文 (保持你写的逻辑，没问题) ================== */
.macro SAVE_CONTEXT
    /* 1. 腾出栈空间: 34 * 8 = 272 bytes */
    addi.d  $sp, $sp, -272

    /* 2. 保存通用寄存器 */
    st.d    $r1,  $sp, 8*1   /* ra */
    st.d    $r2,  $sp, 8*2   /* tp */
    /* r3 (sp) 稍后处理 */
    st.d    $r4,  $sp, 8*4   /* a0 */
    st.d    $r5,  $sp, 8*5
    st.d    $r6,  $sp, 8*6
    st.d    $r7,  $sp, 8*7
    st.d    $r8,  $sp, 8*8
    st.d    $r9,  $sp, 8*9
    st.d    $r10, $sp, 8*10
    st.d    $r11, $sp, 8*11
    st.d    $r12, $sp, 8*12
    st.d    $r13, $sp, 8*13
    st.d    $r14, $sp, 8*14
    st.d    $r15, $sp, 8*15
    st.d    $r16, $sp, 8*16
    st.d    $r17, $sp, 8*17
    st.d    $r18, $sp, 8*18
    st.d    $r19, $sp, 8*19
    st.d    $r20, $sp, 8*20
    st.d    $r21, $sp, 8*21
    st.d    $r22, $sp, 8*22  /* fp */
    st.d    $r23, $sp, 8*23
    st.d    $r24, $sp, 8*24
    st.d    $r25, $sp, 8*25
    st.d    $r26, $sp, 8*26
    st.d    $r27, $sp, 8*27
    st.d    $r28, $sp, 8*28
    st.d    $r29, $sp, 8*29
    st.d    $r30, $sp, 8*30
    st.d    $r31, $sp, 8*31

    /* 3. 保存特殊寄存器 CSR */
    csrrd   $t0, 0x6   /* CSR_ERA */
    st.d    $t0, $sp, 8*32
    csrrd   $t0, 0x1   /* CSR_PRMD */
    st.d    $t0, $sp, 8*33

    /* 4. 将当前的 SP 保存到 TCB 中 */
    la.global $t0, pxCurrentTCB
    ld.d      $t1, $t0, 0       
    st.d      $sp, $t1, 0       
.endm

/* ================== 宏定义：恢复上下文 (保持你的逻辑) ================== */
.macro RESTORE_CONTEXT
    /* 1. 从 pxCurrentTCB 获取 SP */
    la.global $t0, pxCurrentTCB
    ld.d      $t1, $t0, 0       
    ld.d      $sp, $t1, 0       

    /* 2. 恢复特殊寄存器 */
    ld.d      $t0, $sp, 8*33
    csrwr     $t0, 0x1          /* CSR_PRMD */
    ld.d      $t0, $sp, 8*32
    csrwr     $t0, 0x6          /* CSR_ERA */

    /* 3. 恢复通用寄存器 */
    ld.d    $r1,  $sp, 8*1
    ld.d    $r2,  $sp, 8*2
    ld.d    $r4,  $sp, 8*4
    ld.d    $r5,  $sp, 8*5
    ld.d    $r6,  $sp, 8*6
    ld.d    $r7,  $sp, 8*7
    ld.d    $r8,  $sp, 8*8
    ld.d    $r9,  $sp, 8*9
    ld.d    $r10, $sp, 8*10
    ld.d    $r11, $sp, 8*11
    ld.d    $r12, $sp, 8*12
    ld.d    $r13, $sp, 8*13
    ld.d    $r14, $sp, 8*14
    ld.d    $r15, $sp, 8*15
    ld.d    $r16, $sp, 8*16
    ld.d    $r17, $sp, 8*17
    ld.d    $r18, $sp, 8*18
    ld.d    $r19, $sp, 8*19
    ld.d    $r20, $sp, 8*20
    ld.d    $r21, $sp, 8*21
    ld.d    $r22, $sp, 8*22
    ld.d    $r23, $sp, 8*23
    ld.d    $r24, $sp, 8*24
    ld.d    $r25, $sp, 8*25
    ld.d    $r26, $sp, 8*26
    ld.d    $r27, $sp, 8*27
    ld.d    $r28, $sp, 8*28
    ld.d    $r29, $sp, 8*29
    ld.d    $r30, $sp, 8*30
    ld.d    $r31, $sp, 8*31

    /* 4. 回收栈空间 */
    addi.d  $sp, $sp, 272

    /* 5. 异常返回 */
    ertn
.endm

/* ========================================================================== */
/* 函数：启动第一个任务 */
/* ========================================================================== */
xPortStartFirstTask:
    /* 注意：这里直接恢复新任务的上下文，不需要保存旧的 */
    /* 因为这是 Main 函数跳转过来的单行道 */
    RESTORE_CONTEXT

/* ========================================================================== */
/* 统一的异常/中断处理入口 */
/* (这是 start.S 中 EENTRY 指向的地方) */
/* ========================================================================== */
.align 4
freertos_loongarch_trap_handler:
    /* 1. 先保存现场！这一步必须最先做，否则寄存器会被破坏 */
    SAVE_CONTEXT

    /* 2. 读取 CSR_ESTAT (0x5) 来判断是谁触发的 */
    csrrd   $t0, 0x5
    
    /* 3. 分发逻辑 */
    
    /* A. 检查 Syscall (Yield) -> ECODE 位 (21:16) 是否为 0xB */
    srli.d  $t1, $t0, 16
    andi    $t1, $t1, 0x3F
    li.d    $t2, 0xB
    beq     $t1, $t2, handle_yield

    /* B. 检查 Timer 中断 -> 检查中断标志位 (例如 bit 11, TI) */
    li.d    $t2, 0x800      /* 1 << 11 */
    and     $t1, $t0, $t2
    bnez    $t1, handle_tick

    /* 其他未知中断，直接退出恢复 */
    b       exit_trap

/* --- 处理任务切换 (Syscall) --- */
handle_yield:
    /* 【关键修正】Syscall 触发时，ERA 指向 syscall 指令本身 */
    /* 我们必须手动将 ERA + 4，否则 ertn 返回后会死循环执行 syscall */
    ld.d    $t0, $sp, 8*32  /* 从栈里读出保存的 ERA */
    addi.d  $t0, $t0, 4     /* 跳过当前指令 (4字节) */
    st.d    $t0, $sp, 8*32  /* 写回栈里 */

    /* 调用 FreeRTOS 切换上下文 */
    bl      vTaskSwitchContext
    b       exit_trap

/* --- 处理定时器中断 (Tick) --- */
handle_tick:
    /* 1. 清除定时器中断标志 (CSR_TICLR 0x44) */
    li.d    $t0, 1
    csrwr   $t0, 0x44 

    /* 2. 告诉 FreeRTOS 时间流逝 */
    bl      xTaskIncrementTick

    /* 3. 如果 xTaskIncrementTick 返回非 0 ($a0/$r4 != 0)，说明需要切换任务 */
    beq     $r4, $zero, exit_trap
    
    /* 需要切换 */
    bl      vTaskSwitchContext
    b       exit_trap

/* --- 统一出口 --- */
exit_trap:
    RESTORE_CONTEXT
