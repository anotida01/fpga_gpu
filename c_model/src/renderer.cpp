// #include <GL/glut.h>
#include <GL/freeglut.h>
#include <math.h>
#include <time.h>

#include "renderer.h"
#include "main.h"
#include "obj.h"
#include "matrix.h"
#include "transform.h"
#include "algorithms.h"
#include "animate.h"
#include "cmodel_core.h"

#define GUI_MODE_ROT_LIGHT 1
#define GUI_MODE_ROT_OBJ 2
int GUI_MODE = GUI_MODE_ROT_LIGHT;

#define ANI_MODE_FALSE 0
#define ANI_MODE_TRUE 1
int ANI_MODE = ANI_MODE_FALSE;

int REN_REFRESH_CLR = 0;

// draw a single point to openGL
inline void gl_point(int x, int y, colour* p){

    float diff = 1.0 / 2.0;

    glBegin(GL_QUADS);
        glColor3f((float)p->red, (float)p->green, (float)p->blue);
        glVertex2f(x - diff, y - diff);
        glVertex2f(x + diff, y - diff);
        glVertex2f(x + diff, y + diff);
        glVertex2f(x - diff, y + diff);
    glEnd();

    // flushing after every point is drawn slows down rendering
    // use to slow things down and watch
    // glFlush();

    return;

}


// paint the contents of the framebuffer with an algorithm
void ren_refresh() {
    
    if (REN_REFRESH_CLR){
        glClearColor(0.2f, 0.2f, 0.2f, 0.0f); // Set OpenGL background color
        glClear(GL_COLOR_BUFFER_BIT);         // Clear OpenGL colour buffer (background)
    }
    
    // loop through framebuffer and draw to OpenGL
    // for (size_t x = 0; x < H_SIZE; x++)
    //     for (size_t y = 0; y < V_SIZE; y++)
    //         gl_point(x, y, &FRAMEBUFFER[y][x]);

    // Draw outline of valid framebuffer grid (V_SIZE x H_SIZE) pixels to OpenGL
    glBegin(GL_LINE_LOOP);             
        glColor4f(1.0f, 1.0f, 1.0f, 1.0f); // white
        glVertex2i(0, 0);    // x, y
        glVertex2i(0, V_SIZE);
        glVertex2i(H_SIZE, V_SIZE);
        glVertex2i(H_SIZE, 0);
    glEnd();
    
    // Tell OpenGL To Render
    glFlush();
}


void ren_text_write(int x, int y, char* text){

    unsigned char* u_text = (unsigned char*) text;

    glBegin(GL_POINT);
        glColor3f(1.0f, 1.0f, 1.0f);
    glEnd();

    glRasterPos2i(x, y);
    glutBitmapString(GLUT_BITMAP_HELVETICA_18, u_text);

}


// GL pixel hook: the shared pure fb_write (cmodel_core.cpp) writes the
// pixel to FRAMEBUFFER; this hook additionally draws it into the GL canvas
// so the display target's live animation keeps working.
static int _gl_pixel_hook(int x, int y, const colour *p){
    gl_point(x, y, (colour *)p);
    return 0;
}

// clear framebuffer
void ren_fb_clear(){
    
    // colour clear; clear.red=0.2f; clear.green=0.2f; clear.blue=0.2f;
    // for (size_t x = 0; x < H_SIZE; x++)
    //     for (size_t y = 0; y < V_SIZE; y++)
    //         FRAMEBUFFER[y][x] = clear;

    glClearColor(0.2f, 0.2f, 0.2f, 0.0f); // Set OpenGL background color
    glClear(GL_COLOR_BUFFER_BIT);         // Clear OpenGL colour buffer (background)
}


void regular_key_handler(unsigned char key, int x, int y){

    switch (key){

    case 'm':
    case 'M':
        if (GUI_MODE == GUI_MODE_ROT_LIGHT){
            GUI_MODE = GUI_MODE_ROT_OBJ;
        } else {
            GUI_MODE = GUI_MODE_ROT_LIGHT;
            LIGHT = XFORMED_LIGHT; // update global light model
        }
        break;

    case 'a':
    case 'A':
        if (ANI_MODE == ANI_MODE_TRUE) {
            LIGHT = XFORMED_LIGHT; // update global light model
            ANI_MODE = ANI_MODE_FALSE;
        }
        else
            ANI_MODE = ANI_MODE_TRUE;
        break;

    default:
        break;
    }

    return;


}


void special_key_handler(int key, int x, int y){

    ren_fb_clear();

    float FIVE_DEGREES = 5 * M_PI/180;

    std::vector<triangle>* object;
    
    // make a local copy of light for model xforms
    vertex light = LIGHT; 

    if (GUI_MODE == GUI_MODE_ROT_LIGHT)
        object = copy_obj(RASTER_SPACE_OBJ);
    else
        object = copy_obj(OBJ);

    switch (key){
    case GLUT_KEY_RIGHT:
        if (GUI_MODE == GUI_MODE_ROT_LIGHT){
            rotate_2d(&LIGHT, (F)(-1*FIVE_DEGREES));
        }
        else{
            rotate_3d(object, &light, (F)0, (F)0, (F)(-1*FIVE_DEGREES));
        }

        break;
    case GLUT_KEY_LEFT:
        if (GUI_MODE == GUI_MODE_ROT_LIGHT)
            rotate_2d(&LIGHT, (F)FIVE_DEGREES);
        else{
            rotate_3d(object, &light, (F)0, (F)0, (F)FIVE_DEGREES);
        }
        break;
    case GLUT_KEY_UP:
        if (GUI_MODE == GUI_MODE_ROT_LIGHT)
            LIGHT.z += (F)0.1;
        else{
            rotate_3d(object, &light, (F)(FIVE_DEGREES/2.0), (F)0, (F)0);
        }
        break;
    case GLUT_KEY_DOWN:
        if (GUI_MODE == GUI_MODE_ROT_LIGHT)
            LIGHT.z -= (F)0.1;
        else{
            rotate_3d(object, &light, (F)(-1*FIVE_DEGREES/2.0), (F)0, (F)0);
        }
        break;
    default:
        return;
    }

    if (GUI_MODE == GUI_MODE_ROT_OBJ){
        zb_init((SF)100);

        // scale_to_raster_obj(object);

        // update the raster space model
        delete RASTER_SPACE_OBJ;
        RASTER_SPACE_OBJ = copy_obj(object);
        shade_obj(object, &light);

    } else {
        shade_obj(object, &LIGHT);
    }

    draw_obj(object);
    delete object;

    ren_refresh();

}


// Initialize Window & Canvas
void start_renderer(int argc, char** argv){

    // GLUT Window
    glutInit(&argc, argv);
    glutCreateWindow("OBJ Renderer");
    // glutInitWindowSize(1000, 1000);
    // glutInitWindowPosition(50, 50);
    glutReshapeWindow(H_SIZE*3, V_SIZE*3);
    glutPositionWindow(0, 0);

    // GLUT Callbacks
    glutDisplayFunc(ren_refresh);
    glutSpecialFunc(special_key_handler);
    glutKeyboardFunc(regular_key_handler);
    glutIdleFunc(animate);

    // setup GL canvas to match VGA Co-ord system
    gluOrtho2D(-10, H_SIZE+10, V_SIZE+10, -10);

    // route the shared pure fb_write to also draw each pixel into the GL canvas
    cmodel_set_pixel_hook(_gl_pixel_hook);

    glutMainLoop();
    
}
