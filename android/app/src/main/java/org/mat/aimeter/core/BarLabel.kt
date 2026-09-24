package org.mat.aimeter.core

fun barValueLabel(bar: Bar): String = if (bar.fresh) "unused" else "${bar.pct}%"
