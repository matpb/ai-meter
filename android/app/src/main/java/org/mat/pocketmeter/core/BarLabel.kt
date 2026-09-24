package org.mat.pocketmeter.core

fun barValueLabel(bar: Bar): String = if (bar.fresh) "unused" else "${bar.pct}%"
