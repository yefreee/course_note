---
layout: page
title: Home Page
date: 2023-04-18
tags: 
---

<style>
/* 定义两门课程并排的容器 */
.course-container {
    display: block;
}

/* 针对两门课程内部列表项的微调（可选） */
.course-column div {
    margin-bottom: 8px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}

/* 当屏幕宽度大于 768px（电脑端）时启用双列并排 */
@media (min-width: 768px) {
    .course-container {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 0 40px; /* 调整两列之间的间距 */
    }
}
</style>

<div class="course-container">

    <div class="course-column">
        <h2>Linux Shell编程-48课时</h2>
        <div>1. {% post_link linux_shell/1.Shell初识、编辑器的使用 %}</div>
        <div>2. {% post_link linux_shell/2.构建基本脚本 %}</div>
        <div>3. {% post_link linux_shell/3.Shell条件测试 %}</div>
        <div>4. {% post_link linux_shell/4.Shell循环 %}</div>
        <div>5. {% post_link linux_shell/5.处理用户输入 %}</div>
        <div>6. {% post_link linux_shell/6.使用重定向呈现数据 %}</div>
        <div>7. {% post_link linux_shell/7.Shell函数 %}</div>
        <div>8. {% post_link linux_shell/8.正则表达式 %}</div>
        <div>9. {% post_link linux_shell/9.流编辑器sed %}</div>
        <div>10. {% post_link linux_shell/10.文本处理工具awk %}</div>
        <div>11. {% post_link linux_shell/11.监控脚本构建-监控脚本框架与基础运行环境检测 %}</div>
        <div>12. {% post_link linux_shell/12.监控脚本构建-交互式菜单与存储资源监控 %}</div>
        <div>13. {% post_link linux_shell/13.监控脚本构建-内存、存储与流量监控 %}</div>
        <div>14. {% post_link linux_shell/14.多机部署MySQL %}</div>
    </div>

    <div class="course-column">
        <h2>私有云服务架构与运维-64课时</h2>
        <div>1. {% post_link private_clouds/1.云计算与OpenStack %}</div>
        <div>2. {% post_link private_clouds/2.OpenStack基础操作 %}</div>
        <div>3. {% post_link private_clouds/3.OpenStack身份管理 %}</div>
        <div>4. {% post_link private_clouds/4.OpenStack镜像管理 %}</div>
        <div>5. {% post_link private_clouds/5.OpenStack镜像制作 %}</div>
        <div>6. {% post_link private_clouds/6.OpenStack实例管理（一） %}</div>
        <div>7. {% post_link private_clouds/7.OpenStack实例管理（二） %}</div>
        <div>8. {% post_link private_clouds/8.OpenStack虚拟网络 %}</div>
        <div>9. {% post_link private_clouds/9.OpenStack存储管理-Cinder %}</div>
        <div>10. {% post_link private_clouds/10.OpenStack存储管理-Swift %}</div>
        <div>11. {% post_link private_clouds/11.OpenStack编排服务 %}</div>
        <div>12. {% post_link private_clouds/12.OpenStack计量服务 %}</div>
        <div>13. {% post_link private_clouds/13.OpenStack运维案例 %}</div>
    </div>

</div>