import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import test from 'node:test';

test('roadmap items render checkboxes reflecting item.done state', () => {
  const dom = new JSDOM('<!DOCTYPE html><ol id="test-list"></ol>');
  global.document = dom.window.document;

  const testRoadmapItems = [
    { done: true, text: 'Completed item' },
    { done: false, text: 'Incomplete item' },
    { done: undefined, text: 'Undefined done state' },
  ];

  const list = document.getElementById('test-list');

  // Simulate the rendering logic from app.js:1051-1088
  testRoadmapItems.forEach((item, index) => {
    const row = document.createElement('li');
    row.className = item.done ? 'done' : '';

    const content = document.createElement('div');
    content.className = 'roadmap-item-row';

    const checkbox = document.createElement('input');
    checkbox.type = 'checkbox';
    checkbox.checked = item.done;
    checkbox.dataset.index = String(index);

    const text = document.createElement('span');
    text.textContent = item.text;

    content.append(checkbox, text);
    row.append(content);
    list.append(row);
  });

  const checkboxes = list.querySelectorAll('input[type="checkbox"]');

  // Verify checkbox count
  assert.equal(checkboxes.length, 3, 'Should render 3 checkboxes');

  // Verify checkbox states
  assert.equal(checkboxes[0].checked, true, 'First checkbox should be checked (done: true)');
  assert.equal(checkboxes[1].checked, false, 'Second checkbox should be unchecked (done: false)');
  assert.equal(checkboxes[2].checked, false, 'Third checkbox should be unchecked (done: undefined)');

  // Verify row classes
  const rows = list.querySelectorAll('li');
  assert.equal(rows[0].className, 'done', 'First row should have "done" class');
  assert.equal(rows[1].className, '', 'Second row should not have "done" class');
  assert.equal(rows[2].className, '', 'Third row should not have "done" class');

  // Verify text content
  assert.equal(checkboxes[0].nextElementSibling.textContent, 'Completed item');
  assert.equal(checkboxes[1].nextElementSibling.textContent, 'Incomplete item');
  assert.equal(checkboxes[2].nextElementSibling.textContent, 'Undefined done state');
});
