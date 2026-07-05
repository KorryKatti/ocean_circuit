package main

import rl "vendor:raylib"
import rlimgui "../lib/imgui_impl_raylib"
import imgui "../lib/odin-imgui"

App :: struct {
    counter:      int,
    slider:       f32,
    color:        [3]f32,
    show_demo:    bool,
    selected:     int,
    progress:     f32,
    progress_dir: f32,
    frame_count:  int,
}

items := [?]cstring {
    "Apple", "Banana", "Cherry", "Date", "Elderberry"
}

main :: proc() {
    rl.SetConfigFlags({.WINDOW_RESIZABLE, .WINDOW_ALWAYS_RUN})
    rl.InitWindow(1280, 720, "Ocean Circuit")
    defer rl.CloseWindow()

    rl.SetTargetFPS(60)

    imgui.CreateContext(nil)
    defer imgui.DestroyContext(nil)

    io := imgui.GetIO()
    io.ConfigFlags |= {.NavEnableKeyboard}

    rlimgui.init()
    defer rlimgui.shutdown()

    app: App
    app.slider = 0.5
    app.color = {0.2, 0.5, 0.8}
    app.show_demo = true
    app.progress_dir = 1

    for !rl.WindowShouldClose() {
        app.frame_count += 1
        app.progress += app.progress_dir * 0.005
        if app.progress >= 1 { app.progress_dir = -1 }
        if app.progress <= 0 { app.progress_dir = 1 }

        rl.BeginDrawing()
        rl.ClearBackground({20, 20, 25, 255})

        rlimgui.begin()

        if app.show_demo {
            imgui.ShowDemoWindow(&app.show_demo)
        }

        draw_main_window(&app)
        draw_controls_window(&app)

        rlimgui.end()
        rl.EndDrawing()
    }
}

draw_main_window :: proc(app: ^App) {
    imgui.SetNextWindowSize({480, 400}, .FirstUseEver)
    if imgui.Begin("Ocean Circuit") {
        imgui.Text("Welcome to Ocean Circuit")
        imgui.Separator()

        imgui.Text("Frame: %d", app.frame_count)
        imgui.Text("FPS: %d", rl.GetFPS())
        imgui.Text("Delta: %.4f s", rl.GetFrameTime())
        imgui.Separator()

        imgui.Text("Counter:")
        imgui.SameLine()
        if imgui.Button("+##inc") { app.counter += 1 }
        imgui.SameLine()
        if imgui.Button("-##dec") { app.counter -= 1 }
        imgui.SameLine()
        imgui.Text("%d", app.counter)

        imgui.Separator()
        imgui.Text("Slider:")
        imgui.SameLine()
        imgui.SliderFloat("##slider", &app.slider, 0, 1)

        imgui.Separator()
        imgui.Text("Color Picker:")
        imgui.ColorEdit3("##color", &app.color)

        imgui.Separator()
        imgui.Text("Progress Bar:")
        imgui.ProgressBar(app.progress, {-1, 0}, nil)

        imgui.Separator()
        imgui.Text("Combo Box:")
        if imgui.BeginCombo("##combo", items[app.selected]) {
            for i in 0..<len(items) {
                if imgui.Selectable(items[i], i == app.selected) {
                    app.selected = i
                }
            }
            imgui.EndCombo()
        }

        imgui.Separator()
        imgui.Checkbox("Show ImGui Demo Window", &app.show_demo)
    }
    imgui.End()
}

draw_controls_window :: proc(app: ^App) {
    imgui.SetNextWindowSize({300, 200}, .FirstUseEver)
    imgui.SetNextWindowPos({800, 50}, .FirstUseEver)
    if imgui.Begin("Controls") {
        imgui.Text("Keyboard Shortcuts:")
        imgui.BulletText("ESC - Close window")
        imgui.BulletText("TAB - Navigate widgets")
        imgui.BulletText("Click + Drag - Interact")
        imgui.Separator()
        imgui.Text("Mouse:")
        imgui.BulletText("Left Click - Select")
        imgui.BulletText("Right Click - Pan (ImGui)")
        imgui.BulletText("Scroll - Zoom/Scroll")
    }
    imgui.End()
}
