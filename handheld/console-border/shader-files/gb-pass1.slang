#version 450

layout(push_constant) uniform Push
{
	vec4 OutputSize;
	vec4 OriginalSize;
	vec4 SourceSize;
	float blending_mode;
	float adjacent_texel_alpha_blending;
} registers;

layout(std140, set = 0, binding = 0) uniform UBO
{
    mat4 MVP;
} global;

////////////////////////////////////////////////////////////////////////////////
// Config                                                                     //
////////////////////////////////////////////////////////////////////////////////

// 0 - only the space between dots is blending
// 1 - all texels are blended
#pragma parameter blending_mode "Blending Mode" 0.0 0.0 1.0 1.0            

// The amount of alpha swapped between neighboring texels
#pragma parameter adjacent_texel_alpha_blending "Neighbor Blending" 0.38 0.0 1.0 0.01

///////////////////////////////////////////////////////////////////////////
//                                                                       //
// Gameboy Classic Shader v0.2.2                                         //
//                                                                       //
// Copyright (C) 2013 Harlequin : unknown92835@gmail.com                 //
//                                                                       //
// This program is free software: you can redistribute it and/or modify  //
// it under the terms of the GNU General Public License as published by  //
// the Free Software Foundation, either version 3 of the License, or     //
// (at your option) any later version.                                   //
//                                                                       //
// This program is distributed in the hope that it will be useful,       //
// but WITHOUT ANY WARRANTY; without even the implied warranty of        //
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         //
// GNU General Public License for more details.                          //
//                                                                       //
// You should have received a copy of the GNU General Public License     //
// along with this program.  If not, see <http://www.gnu.org/licenses/>. //
//                                                                       //
///////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// Vertex shader                                                              //
////////////////////////////////////////////////////////////////////////////////

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;
layout(location = 1) out vec2 texel;
layout(location = 2) out vec2 blur_coords_up;
layout(location = 3) out vec2 blur_coords_down;
layout(location = 4) out vec2 blur_coords_right;
layout(location = 5) out vec2 blur_coords_left;
layout(location = 6) out vec2 blur_coords_upright;
layout(location = 7) out vec2 blur_coords_upleft;
layout(location = 8) out vec2 blur_coords_downright;
layout(location = 9) out vec2 blur_coords_downleft;
layout(location = 10) out vec2 blur_coords_lower_bound;
layout(location = 11) out vec2 blur_coords_upper_bound;

void main()
{
    gl_Position = global.MVP * Position;
    vTexCoord = TexCoord;

    texel = registers.SourceSize.zw;
    blur_coords_down        = vTexCoord + vec2(0.0, texel.y);
    blur_coords_up          = vTexCoord + vec2(0.0, -texel.y);
    blur_coords_right       = vTexCoord + vec2(texel.x,  0.0);
    blur_coords_left        = vTexCoord + vec2(-texel.x, 0.0);
    blur_coords_downright   = vTexCoord + vec2(texel.x, texel.y);
    blur_coords_downleft    = vTexCoord + vec2(-texel.x, texel.y);
    blur_coords_upright     = vTexCoord + vec2(texel.x, -texel.y);
    blur_coords_upleft      = vTexCoord + vec2(-texel.x, -texel.y);

    blur_coords_lower_bound = vec2(0.0);
    blur_coords_upper_bound = texel * (registers.OutputSize.xy - vec2(2.0));
}

////////////////////////////////////////////////////////////////////////////////
// Fragment shader                                                            //
////////////////////////////////////////////////////////////////////////////////

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 1) in vec2 texel;
layout(location = 2) in vec2 blur_coords_up;
layout(location = 3) in vec2 blur_coords_down;
layout(location = 4) in vec2 blur_coords_right;
layout(location = 5) in vec2 blur_coords_left;
layout(location = 6) in vec2 blur_coords_upright;
layout(location = 7) in vec2 blur_coords_upleft;
layout(location = 8) in vec2 blur_coords_downright;
layout(location = 9) in vec2 blur_coords_downleft;
layout(location = 10) in vec2 blur_coords_lower_bound;
layout(location = 11) in vec2 blur_coords_upper_bound;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;

////////////////////////////////////////////////////////////////////////////////
// Fragment definitions                                                       //
////////////////////////////////////////////////////////////////////////////////

bool is_gap(vec2 coords_side_1, vec2 coords_side_2)
{
    float color = texture(Source, vTexCoord).a;
    float color_side_1 = texture(Source, coords_side_1).a;
    float color_side_2 = texture(Source, coords_side_2).a;

    return color == 0.0 && color_side_1 == 0.0 && color_side_2 == 0.0;
}

float blending_modifier(float color)
{
	float blend_bool = (color == 0.0) ? 1 : 0;
	return clamp(blend_bool + registers.blending_mode, 0.0, 1.0);
}

// Clamp the blur coords to the input texture size so it doesn't attempt to sample off the texture (it'll retrieve float4(0.0) and darken the edges otherwise)
vec2 blur_coords_clamp(vec2 blur_coords)
{
    return clamp(blur_coords, blur_coords_lower_bound, blur_coords_upper_bound);
}

void main()
{
    // A simple blur technique that softens harsh color transitions
    // Specialized to only blur alpha values and limited to only blurring texels
    // lying in the spaces between two or more texels

    // Sample the input textures
    vec4 out_color = texture(Source, vTexCoord).rgba;

    // Sum the alpha differences between neighboring texels, apply modifiers, then subtract the result from the current fragment alpha value

    bool is_gap_horizontal = is_gap(blur_coords_left, blur_coords_right);
    bool is_gap_vertical = is_gap(blur_coords_up, blur_coords_down);

    if(is_gap_horizontal && is_gap_vertical)
    {
        float adjacent_texel_alpha_upleft    = texture(Source, blur_coords_clamp(blur_coords_upleft)).a;
        float adjacent_texel_alpha_upright   = texture(Source, blur_coords_clamp(blur_coords_upright)).a;
        float adjacent_texel_alpha_downleft  = texture(Source, blur_coords_clamp(blur_coords_downleft)).a;
        float adjacent_texel_alpha_downright = texture(Source, blur_coords_clamp(blur_coords_downright)).a;

        out_color.a -=  
        (
            (out_color.a - adjacent_texel_alpha_upleft) +
            (out_color.a - adjacent_texel_alpha_upright) +
            (out_color.a - adjacent_texel_alpha_downleft) +
            (out_color.a - adjacent_texel_alpha_downright)
        ) * (registers.adjacent_texel_alpha_blending / 2) * blending_modifier(out_color.a);
    }
    else if(is_gap_horizontal)
    {
        float adjacent_texel_alpha_up   = texture(Source, blur_coords_clamp(blur_coords_up)).a;
        float adjacent_texel_alpha_down = texture(Source, blur_coords_clamp(blur_coords_down)).a;

        out_color.a -=  
        (
            (out_color.a - adjacent_texel_alpha_up) +
            (out_color.a - adjacent_texel_alpha_down)
        ) * registers.adjacent_texel_alpha_blending * blending_modifier(out_color.a);
    }
    else if(is_gap_vertical)
    {
        float adjacent_texel_alpha_right = texture(Source, blur_coords_clamp(blur_coords_right)).a;
        float adjacent_texel_alpha_left  = texture(Source, blur_coords_clamp(blur_coords_left)).a;

        out_color.a -=  
        (
            (out_color.a - adjacent_texel_alpha_right) +
            (out_color.a - adjacent_texel_alpha_left)
        ) * registers.adjacent_texel_alpha_blending * blending_modifier(out_color.a);
    }

    FragColor = out_color;
}
