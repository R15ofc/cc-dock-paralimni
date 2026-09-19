#!/usr/bin/env python3
import argparse
import heapq
import json
import math
import struct
from collections import deque
from pathlib import Path


MAGIC = 0x52524D31
DRIVABLE = 1 | 2 | 4
NEIGHBORS = (
    (-1, -1, math.sqrt(2)), (0, -1, 1), (1, -1, math.sqrt(2)),
    (-1, 0, 1), (1, 0, 1),
    (-1, 1, math.sqrt(2)), (0, 1, 1), (1, 1, math.sqrt(2)),
)


def load_map(path):
    payload = path.read_bytes()
    magic, count = struct.unpack_from(">II", payload, 0)
    if magic != MAGIC:
        raise ValueError("invalid RRM1 map")
    cells = {}
    offset = 8
    for _ in range(count):
        x, z, y, flags = struct.unpack_from(">iihB", payload, offset)
        offset += 11
        if flags & DRIVABLE:
            cells[(x, z)] = (y, flags)
    return cells


def largest_component(cells):
    remaining = set(cells)
    largest = set()
    while remaining:
        start = remaining.pop()
        component = {start}
        queue = [start]
        while queue:
            x, z = queue.pop()
            for dx, dz, _ in NEIGHBORS:
                neighbor = (x + dx, z + dz)
                if neighbor in remaining:
                    remaining.remove(neighbor)
                    component.add(neighbor)
                    queue.append(neighbor)
        if len(component) > len(largest):
            largest = component
    return largest


def astar(cells, start, target, limit=120000):
    open_nodes = [(math.dist(start, target), 0.0, start)]
    costs = {start: 0.0}
    parents = {start: None}
    visited = 0
    while open_nodes and visited < limit:
        _, cost, current = heapq.heappop(open_nodes)
        if cost != costs.get(current):
            continue
        visited += 1
        if current == target:
            path = []
            while current is not None:
                path.append(current)
                current = parents[current]
            path.reverse()
            return path, visited
        x, z = current
        for dx, dz, move_cost in NEIGHBORS:
            neighbor = (x + dx, z + dz)
            if neighbor not in cells:
                continue
            next_cost = cost + move_cost
            if next_cost >= costs.get(neighbor, math.inf):
                continue
            costs[neighbor] = next_cost
            parents[neighbor] = current
            score = next_cost + math.dist(neighbor, target)
            heapq.heappush(open_nodes, (score, next_cost, neighbor))
    return None, visited


def compress(path):
    result = []
    previous_direction = None
    for index, point in enumerate(path):
        if index + 1 < len(path):
            next_point = path[index + 1]
            direction = (
                (next_point[0] > point[0]) - (next_point[0] < point[0]),
                (next_point[1] > point[1]) - (next_point[1] < point[1]),
            )
        else:
            direction = previous_direction
        if index == 0 or index == len(path) - 1 or direction != previous_direction or index % 12 == 0:
            result.append(point)
        previous_direction = direction
    return result


def route_checks(cells):
    component = largest_component(cells)
    points = list(component)
    extremes = [
        min(points, key=lambda point: point[0]),
        max(points, key=lambda point: point[0]),
        min(points, key=lambda point: point[1]),
        max(points, key=lambda point: point[1]),
    ]
    pairs = ((extremes[0], extremes[1]), (extremes[2], extremes[3]), (extremes[0], extremes[3]))
    checks = []
    for start, target in pairs:
        path, visited = astar(component, start, target)
        checks.append({
            "start": start,
            "target": target,
            "available": path is not None,
            "visited": visited,
            "cells": len(path) if path else 0,
            "waypoints": len(compress(path)) if path else 0,
        })
    return component, checks


def normalize_angle(value):
    while value > math.pi:
        value -= math.pi * 2
    while value < -math.pi:
        value += math.pi * 2
    return value


def point_segment_distance(point, first, second):
    dx, dz = second[0] - first[0], second[1] - first[1]
    length_squared = dx * dx + dz * dz
    if length_squared == 0:
        return math.dist(point, first)
    t = max(0, min(1, ((point[0] - first[0]) * dx + (point[1] - first[1]) * dz) / length_squared))
    projection = (first[0] + dx * t, first[1] + dz * t)
    return math.dist(point, projection)


def route_distance(point, route):
    return min(point_segment_distance(point, route[index], route[index + 1]) for index in range(len(route) - 1))


def route_geometry(position, speed, route, lookahead_base, lookahead_gain):
    nearest = min(range(len(route)), key=lambda index: math.dist(position, route[index]))
    wanted = max(4, min(16, lookahead_base + speed * lookahead_gain))
    target_index = nearest
    walked = 0
    previous = position
    while target_index < len(route) - 1 and walked < wanted:
        target_index += 1
        walked += math.dist(previous, route[target_index])
        previous = route[target_index]
    target = route[target_index]
    next_point = route[min(len(route) - 1, target_index + 1)]
    desired = math.atan2(target[1] - position[1], target[0] - position[0])
    next_heading = desired if next_point == target else math.atan2(next_point[1] - target[1], next_point[0] - target[0])
    turn = abs(normalize_angle(next_heading - desired))
    segment = max(1, math.dist(position, target))
    radius = 999 if turn < 0.03 else max(2, segment / max(0.08, 2 * math.sin(turn * 0.5)))
    return desired, turn, radius


def simulate(route, parameters):
    dt = 0.05
    x, z = route[0][0], route[0][1] + 1.5
    heading = math.atan2(route[1][1] - route[0][1], route[1][0] - route[0][0]) + 0.12
    speed = 0.0
    steer = 0.0
    maximum_error = 0.0
    clutch = True
    elapsed = 0.0
    while elapsed < 90:
        desired, turn, radius = route_geometry((x, z), speed, route, parameters[0], parameters[1])
        error = normalize_angle(desired - heading)
        deadzone = max(0.04, min(0.16, parameters[2] + speed * parameters[3]))
        command = 1 if error > deadzone else (-1 if error < -deadzone else 0)
        steer += (command - steer) * min(1, dt * 5.5)
        target_speed = 7.0
        if turn > 0.05:
            target_speed = min(target_speed, math.sqrt(max(1, 1.8 * radius)))
        if turn > 0.45:
            target_speed = min(target_speed, 3.2)
        destination_distance = math.dist((x, z), route[-1])
        if destination_distance < 16:
            target_speed = min(target_speed, max(1.5, destination_distance * 0.35))
        if target_speed <= 0.05:
            clutch = False
        elif speed < target_speed - 0.35:
            clutch = True
        elif speed > target_speed + 0.15:
            clutch = False
        acceleration = 3.2 if clutch else -1.9
        speed = max(0, min(15, speed + acceleration * dt))
        heading = normalize_angle(heading + speed / 5.0 * math.tan(steer * 0.52) * dt)
        x += math.cos(heading) * speed * dt
        z += math.sin(heading) * speed * dt
        maximum_error = max(maximum_error, route_distance((x, z), route))
        elapsed += dt
        if destination_distance <= 2.5 and speed < 1.8:
            break
    return {
        "arrived": math.dist((x, z), route[-1]) <= 4,
        "seconds": round(elapsed, 2),
        "finalDistance": round(math.dist((x, z), route[-1]), 3),
        "maxCrossTrackError": round(maximum_error, 3),
    }


def tune_controller():
    scenarios = {
        "straight": [(0, 0), (24, 0), (48, 0), (72, 0), (96, 0)],
        "corner": [(0, 0), (20, 0), (34, 2), (44, 8), (50, 18), (52, 34), (52, 60)],
        "s_curve": [(value, math.sin(value / 15) * 9) for value in range(0, 121, 8)],
    }
    best = None
    for lookahead_base in (3.0, 3.5, 4.0, 4.5):
        for lookahead_gain in (0.55, 0.7, 0.85, 1.0):
            for deadzone_base in (0.045, 0.06, 0.075):
                for deadzone_gain in (0.004, 0.006, 0.008):
                    parameters = (lookahead_base, lookahead_gain, deadzone_base, deadzone_gain)
                    results = {name: simulate(route, parameters) for name, route in scenarios.items()}
                    failures = sum(not result["arrived"] for result in results.values())
                    score = failures * 1000 + sum(
                        result["finalDistance"] * 8 + result["maxCrossTrackError"] * 3 + result["seconds"] * 0.02
                        for result in results.values()
                    )
                    if best is None or score < best[0]:
                        best = (score, parameters, results)
    return {
        "parameters": {
            "lookaheadBase": best[1][0],
            "lookaheadGain": best[1][1],
            "deadzoneBase": best[1][2],
            "deadzoneGain": best[1][3],
        },
        "scenarios": best[2],
        "score": round(best[0], 3),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("map", type=Path)
    args = parser.parse_args()
    cells = load_map(args.map)
    component, checks = route_checks(cells)
    report = {
        "mapCells": len(cells),
        "largestConnectedRoad": len(component),
        "routes": checks,
        "controller": tune_controller(),
    }
    print(json.dumps(report, indent=2))
    if not all(route["available"] for route in checks):
        raise SystemExit("route validation failed")
    if not all(result["arrived"] for result in report["controller"]["scenarios"].values()):
        raise SystemExit("controller simulation failed")


if __name__ == "__main__":
    main()
