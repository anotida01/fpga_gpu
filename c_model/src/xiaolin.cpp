// C program to implement Xiaolin Wu's line drawing
// algorithm.
// We must install SDL library using above steps
// to run this program
// #include<SDL2/SDL.h>

// SDL stuff
// SDL_Window* pWindow = 0;
// SDL_Renderer* pRenderer = 0;

#include <iostream>

#include "main.h"
#include "renderer.h"

#include "fpm/fixed.hpp"
#include "fpm/ios.hpp"
#include "fpm/math.hpp"

// using fixed_16_5 = fpm::fixed<std::int16_t, std::int32_t, 5>;
// using fixed_16_16 = fpm::fixed_16_16;
// using F = fixed_16_16; // short-hand for casting

void func(){

	// std::cout << "Hello World\n";

	// fixed_16_16 a  = (fixed_16_16)0.612312;

	// fixed_16_16 c[4][4] = {
	// 	{(F)1, (F)0, (F)0, (F)0},
	// 	{(F)0, (F)1, (F)0, (F)0},
	// 	{(F)0, (F)0, (F)1, (F)0},
	// 	{(F)0, (F)0, (F)0, (F)1}
	// };

	// fixed_16_5 s[2] = {static_cast<fixed_16_5>(0.612312), static_cast<fixed_16_5>(0.612312)};

	// fixed_16_5 b[4][4] = static_cast<fixed_16_5> c;

	// std::cout << "Fixed: " << std::scientific << a * c[2][2] << std::endl;

	// exit(0); 
}



// swaps two numbers
void swap(int* a , int*b)
{
	int temp = *a;
	*a = *b;
	*b = temp;
}

// returns absolute value of number
float absolute(float x )
{
	if (x < 0) return -x;
	else return x;
}

//returns integer part of a floating point number
int iPartOfNumber(float x)
{
	return (int)x;
}

//rounds off a number
int roundNumber(float x)
{
	return iPartOfNumber(x + 0.5) ;
}

//returns fractional part of a number
float fPartOfNumber(float x)
{
	if (x>0) return x - iPartOfNumber(x);
	else return x - (iPartOfNumber(x)+1);

}

//returns 1 - fractional part of number
float rfPartOfNumber(float x)
{
	return 1 - fPartOfNumber(x);
}

// draws a pixel on screen of given brightness
// 0<=brightness<=1. We can use your own library
// to draw on screen
void drawPixel( int x , int y , float brightness)
{
	// colour c = {.red = brightness*1.0f, .green = brightness*1.0f, .blue = brightness*1.0f };
	// ren_fb_write(x, y, &c);
}

void drawAALine(int x0 , int y0 , int x1 , int y1)
{
	int steep = absolute(y1 - y0) > absolute(x1 - x0) ;

	// swap the co-ordinates if slope > 1 or we
	// draw backwards
	if (steep)
	{
		swap(&x0 , &y0);
		swap(&x1 , &y1);
	}
	if (x0 > x1)
	{
		swap(&x0 ,&x1);
		swap(&y0 ,&y1);
	}

	//compute the slope
	float dx = x1-x0;
	float dy = y1-y0;
	float gradient = dy/dx;
	if (dx == 0.0)
		gradient = 1;

	int xpxl1 = x0;
	int xpxl2 = x1;
	float intersectY = y0;

	// main loop
	if (steep)
	{
		int x;
		for (x = xpxl1 ; x <=xpxl2 ; x++)
		{
			// pixel coverage is determined by fractional
			// part of y co-ordinate
			drawPixel(iPartOfNumber(intersectY), x,
						rfPartOfNumber(intersectY));
			drawPixel(iPartOfNumber(intersectY)-1, x,
						fPartOfNumber(intersectY));
			intersectY += gradient;
		}
	}
	else
	{
		int x;
		for (x = xpxl1 ; x <=xpxl2 ; x++)
		{
			// pixel coverage is determined by fractional
			// part of y co-ordinate
			drawPixel(x, iPartOfNumber(intersectY),
						rfPartOfNumber(intersectY));
			drawPixel(x, iPartOfNumber(intersectY)-1,
						fPartOfNumber(intersectY));
			intersectY += gradient;
		}
	}

}