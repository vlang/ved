module main

import os
import gx

struct Node {
mut:
	path     string
	is_dir   bool
	expanded bool
	children []int // index of the nodes in []Node array
	depth    int
}

struct Tree {
mut:
	nodes         []Node
	visible_nodes []int
	node_pos      []NodePos
	root          int
}

struct NodePos {
	node_idx int
	x        int
	y        int
	w        int
	h        int
}

fn (mut t Tree) init(workspace_path string) {
	println('init tree workspace=${workspace_path}')
	t.nodes.clear()
	t.nodes << Node{
		path:     workspace_path
		is_dir:   true
		expanded: true // false
		depth:    0
	}
	t.root = 0
	t.load_children(t.root)
	t.refresh()
	//println('TTTT')
	//println(t)
}

fn (mut t Tree) refresh() {
	t.compute_visible_nodes()
	t.compute_layout()
}

fn (mut t Tree) load_children(node_idx int) {
	println('load children ${node_idx}')
	mut node := t.nodes[node_idx]
	println('node=${node}')
	if !node.is_dir || node.children.len > 0 {
		return
	}

	entries := os.ls(node.path) or { return }
	println('entries=${entries}')
	for entry in entries {
		full_path := os.join_path(node.path, entry)
		is_dir := os.is_dir(full_path)
		t.nodes << Node{
			path:   full_path
			is_dir: is_dir
			depth:  node.depth + 1
		}
		t.nodes[node_idx].children << t.nodes.len - 1
	}
}

fn (mut t Tree) compute_visible_nodes() {
	t.visible_nodes.clear()
	mut stack := []int{}
	stack << t.root
	for stack.len > 0 {
		idx := stack.pop()
		t.visible_nodes << idx
		node := t.nodes[idx]
		if node.is_dir && node.expanded {
			for i := node.children.len - 1; i >= 0; i-- {
				stack << node.children[i]
			}
		}
	}
	println('visible afer compute')
	println(t.visible_nodes)
}

fn (mut t Tree) handle_click(x int, y int) {
	for pos in t.node_pos {
		if x >= pos.x && x <= pos.x + pos.w && y >= pos.y && y <= pos.y + pos.h {
			mut node := &t.nodes[pos.node_idx]
			if node.is_dir {
				node.expanded = !node.expanded
				if node.expanded {
					t.load_children(pos.node_idx)
				}
				t.refresh()
			}
			break
		}
	}
}

// Handle mouse clicks:
fn (mut ved Ved) on_click(x int, y int) {
	ved.tree.handle_click(x, y)
}

// Initialize the tree when workspace is set:
fn (mut ved Ved) init_tree() {
	ved.tree.init(ved.workspace)
}

fn (mut t Tree) compute_layout() {
	t.node_pos.clear()
	mut y := 30
	x := 10
	for idx in t.visible_nodes {
		node := t.nodes[idx]
		indent := node.depth * 20
		current_x := x + indent
		text := os.base(node.path)
		w := text.len * 8 + 20 // Account for [+]/[-] symbol
		h := 20
		t.node_pos << NodePos{idx, current_x, y, w, h}
		y += h
	}
}

fn (mut t Tree) draw(mut ved Ved) {
	// println('draw tree')
	for pos in t.node_pos {
		node := t.nodes[pos.node_idx]
		text := os.base(node.path)
		if node.is_dir {
			// Draw expand/collapse symbol
			symbol := if node.expanded { '- ' } else { '+ ' }
			ved.gg.draw_text2(x: pos.x, y: pos.y, text: symbol, color: gx.black)
			ved.gg.draw_text2(x: pos.x + 20, y: pos.y, text: text, color: gx.blue)
		} else {
			ved.gg.draw_text2(x: pos.x + 20, y: pos.y, text: text, color: gx.black)
		}
	}
}
